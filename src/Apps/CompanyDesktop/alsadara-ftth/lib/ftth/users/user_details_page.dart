/// اسم الصفحة: تفاصيل المستخدم
/// وصف الصفحة: صفحة تفاصيل مستخدم محدد
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../subscriptions/subscription_details_page.dart';
// إضافة زر فتح نافذة إضافة مهمة
import '../../task/add_task_api_dialog.dart';
import '../tickets/customer_tickets_page.dart';
import '../reports/audit_log_page.dart';
import '../../permissions/permissions.dart';
import '../auth/auth_error_handler.dart';
import '../../services/auth_service.dart';
import '../../services/task_api_service.dart';
import '../../services/genieacs_service.dart';

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
  // بيانات الوكيل من المهمة (لتعبئة تلقائية في صفحة التجديد)
  final String? taskAgentName;
  final String? taskAgentCode;
  // ملاحظات المهمة (تفاصيل الاشتراك) لتعبئتها تلقائياً في صفحة التجديد
  final String? taskNotes;
  // بيانات المهمة للإغلاق التلقائي والمقارنة
  final String? taskId;
  final String? taskServiceType;
  final String? taskDuration;
  final String? taskAmount;
  const UserDetailsPage(
      {super.key,
      required this.userId,
      required this.userName,
      required this.userPhone,
      required this.authToken,
      required this.activatedBy,
      this.hasServerSavePermission = false,
      this.hasWhatsAppPermission = false,
      this.isAdminFlag,
      this.firstSystemDepartment,
      this.firstSystemCenter,
      this.firstSystemSalary,
      this.ftthPermissions,
      this.userRoleHeader,
      this.clientAppHeader,
      this.importantFtthApiPermissions,
      this.taskAgentName,
      this.taskAgentCode,
      this.taskNotes,
      this.taskId,
      this.taskServiceType,
      this.taskDuration,
      this.taskAmount});
  @override
  UserDetailsPageState createState() => UserDetailsPageState();
}

class UserDetailsPageState extends State<UserDetailsPage> {
  Map<String, dynamic>? subscriptionDetails;
  List<Map<String, dynamic>> _allSubscriptions = [];
  int _selectedSubscriptionIndex = 0;
  Map<String, dynamic>? deviceOntInfo;
  Map<String, dynamic>?
      _deviceFullInfo; // بيانات الجهاز الكاملة (IP + كلمة مرور)
  Map<String, dynamic>? _totalUsageData; // إجمالي الاستهلاك
  bool _isLoadingUsage = false;
  Map<String, dynamic>? _customerDataMain;
  String _resolvedPhone = ''; // رقم الهاتف المُحلَّل
  bool _isFetchingPhone = false; // جاري جلب الهاتف
  bool isLoading = true;
  bool isLoadingOntInfo = false;
  String errorMessage = '';
  String ontErrorMessage = '';
  final bool _compactMode = true;
  // تم استبدال عرض التذاكر في حوار بصفحة مستقلة CustomerTicketsPage

  // ═══════ حالة طلب التحصيل ═══════
  List<Map<String, dynamic>> _collectionTasks = [];
  bool _isLoadingCollectionTasks = false;

  // ═══════ حالة ربط GenieACS ═══════
  bool? _genieAcsLinked; // null = جاري الفحص, true = مرتبط, false = غير مرتبط

  @override
  void initState() {
    super.initState();
    fetchDetails();
    _fetchAndStoreCustomerDetails();
    _checkCollectionTasks();
    _checkGenieAcsStatus();
  }

  Future<void> _checkCollectionTasks() async {
    if (widget.userPhone.isEmpty) return;
    setState(() => _isLoadingCollectionTasks = true);
    try {
      final result = await TaskApiService.instance
          .getCollectionTasks(customerPhone: widget.userPhone);
      if (!mounted) return;
      if (result['success'] == true && result['data'] != null) {
        final data = result['data'];
        final items = data is Map
            ? (data['items'] as List? ?? [])
            : (data is List ? data : []);
        setState(() {
          _collectionTasks = List<Map<String, dynamic>>.from(items);
        });
      }
    } catch (e) {
      debugPrint('⚠️ فشل جلب طلبات التحصيل: $e');
    } finally {
      if (mounted) setState(() => _isLoadingCollectionTasks = false);
    }
  }

  // يسمح بإضافة مهمة إذا تحقق أحد الشروط: isAdminFlag أو صلاحية tasks من PermissionManager
  bool get _canAddTask {
    if (widget.isAdminFlag == true) {
      debugPrint('[UserDetailsPage] isAdminFlag=true => السماح بزر المهمة');
      return true;
    }
    // استخدام PermissionManager بدلاً من فحص النص
    final allowed = PermissionManager.instance.canAdd('tasks');
    debugPrint(
        '[UserDetailsPage] فحص زر المهمة - PermissionManager.canAdd(tasks)=$allowed');
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
    final screenH = MediaQuery.of(context).size.height;
    final double sc = (screenH / 900).clamp(0.75, 1.0);
    final isMobile = _isMobile(context);
    final double fontSize = (isMobile ? 15 : 16) * sc;
    final double vPad = (isMobile ? 12 : 16) * sc;
    final double hPad = (isMobile ? 16 : 20) * sc;
    final Size minSize = Size(140 * sc, 48 * sc);
    return ElevatedButton.styleFrom(
      backgroundColor: Colors.green,
      foregroundColor: Colors.white,
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
      minimumSize: minSize,
      textStyle: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w800),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: const VisualDensity(horizontal: -1, vertical: -1),
    );
  }

  // ---------------- API -----------------
  Future<void> fetchDetails() async {
    try {
      final r = await AuthService.instance.authenticatedRequest('GET',
          'https://admin.ftth.iq/api/customers/subscriptions?customerId=${widget.userId}');
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body);
        final items = data['items'] as List?;
        debugPrint(
            '[fetchDetails] keys=${data.keys.toList()} totalCount=${data['totalCount']} itemsCount=${items?.length}');
        if (mounted) {
          setState(() {
            _allSubscriptions =
                items?.map((e) => Map<String, dynamic>.from(e)).toList() ?? [];
            _selectedSubscriptionIndex = 0;
            subscriptionDetails =
                (_allSubscriptions.isNotEmpty) ? _allSubscriptions.first : null;
          });
        }
      } else if (r.statusCode == 401) {
        if (mounted) AuthErrorHandler.handle401Error(context);
        return;
      } else if (mounted) {
        setState(
            () => errorMessage = 'فشل جلب بيانات الاشتراك: ${r.statusCode}');
      }
    } catch (e) {
      if (mounted) setState(() => errorMessage = 'خطأ');
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
        if (subscriptionDetails != null) {
          fetchDeviceOntInfo();
          _fetchDeviceFullInfo();
          _fetchTotalUsage();
          final id = _extractSubscriptionId(subscriptionDetails!);
          if (id != null && id.isNotEmpty) fetchFullSubscriptionDetails(id);
        }
      }
    }
  }

  Future<void> fetchFullSubscriptionDetails(String id) async {
    try {
      final r = await AuthService.instance.authenticatedRequest(
          'GET', 'https://admin.ftth.iq/api/subscriptions/$id');
      if (r.statusCode == 200 && mounted && subscriptionDetails != null) {
        final full = jsonDecode(r.body);
        final merged =
            Map<String, dynamic>.from({...subscriptionDetails!, ...full});
        setState(() {
          subscriptionDetails = merged;
          // تحديث _allSubscriptions[i] بالبيانات الكاملة حتى لا تُفقد عند التبديل بين الاشتراكات
          if (_selectedSubscriptionIndex < _allSubscriptions.length) {
            _allSubscriptions[_selectedSubscriptionIndex] =
                Map<String, dynamic>.from(merged);
          }
        });
      } else if (r.statusCode == 401) {
        if (mounted) AuthErrorHandler.handle401Error(context);
        return;
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
      _deviceFullInfo = null;
      _totalUsageData = null;
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
      final r = await AuthService.instance.authenticatedRequest('GET',
          'https://admin.ftth.iq/api/subscriptions/device/ont?username=${username.trim()}');
      if (!mounted) return;
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body);
        setState(() {
          deviceOntInfo = data;
          isLoadingOntInfo = false;
        });
      } else if (r.statusCode == 401) {
        if (mounted) AuthErrorHandler.handle401Error(context);
        return;
      } else if (r.statusCode == 404) {
        setState(() {
          ontErrorMessage = 'معلومات الجهاز غير متوفرة لهذا المشترك';
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
          ontErrorMessage = 'خطأ';
          isLoadingOntInfo = false;
        });
      }
    }
  }

  Future<void> _fetchDeviceFullInfo() async {
    if (subscriptionDetails == null) return;
    final id = _extractSubscriptionId(subscriptionDetails!);
    if (id == null || id.isEmpty) return;
    try {
      final r = await AuthService.instance.authenticatedRequest(
          'GET', 'https://admin.ftth.iq/api/subscriptions/$id/device');
      if (!mounted) return;
      debugPrint(
          '[_fetchDeviceFullInfo] status=${r.statusCode} body=${r.body.length > 500 ? r.body.substring(0, 500) : r.body}');
      if (r.statusCode == 200) {
        final parsed = jsonDecode(r.body);
        // بعض الـ APIs ترجع البيانات مباشرة وبعضها داخل model
        Map<String, dynamic>? info;
        if (parsed is Map) {
          final m = Map<String, dynamic>.from(parsed);
          if (m.containsKey('ipAddress')) {
            info = m;
          } else if (m.containsKey('model') && m['model'] is Map) {
            info = Map<String, dynamic>.from(m['model']);
          } else {
            info = m;
          }
        }
        debugPrint(
            '[_fetchDeviceFullInfo] resolved keys=${info?.keys.toList()} ipAddress=${info?['ipAddress']}');
        setState(() => _deviceFullInfo = info);
      }
    } catch (e) {
      debugPrint('[_fetchDeviceFullInfo] error=$e');
    }
  }

  String _usagePeriod = 'all'; // today, month, all — نبدأ بالكل لأنه مضمون

  Future<void> _fetchTotalUsage() async {
    if (subscriptionDetails == null) return;
    final id = _extractSubscriptionId(subscriptionDetails!);
    if (id == null || id.isEmpty) return;
    setState(() => _isLoadingUsage = true);

    String url;
    final now = DateTime.now();
    if (_usagePeriod == 'today') {
      final start = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      url = 'https://admin.ftth.iq/api/subscriptions/$id/sessions/period-usage?PeriodSize=1&StartDate=$start';
    } else if (_usagePeriod == 'month') {
      final start = '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
      url = 'https://admin.ftth.iq/api/subscriptions/$id/sessions/period-usage?PeriodSize=${now.day}&StartDate=$start';
    } else {
      url = 'https://admin.ftth.iq/api/subscriptions/$id/sessions/total-usage';
    }

    try {
      final r = await AuthService.instance.authenticatedRequest('GET', url);
      if (!mounted) return;
      debugPrint('[_fetchTotalUsage] period=$_usagePeriod status=${r.statusCode} body=${r.body.length > 500 ? r.body.substring(0, 500) : r.body}');
      if (r.statusCode == 200) {
        final parsed = jsonDecode(r.body);
        Map<String, dynamic>? usage;
        if (parsed is Map) {
          final m = Map<String, dynamic>.from(parsed);
          if (m.containsKey('model') && m['model'] is Map) {
            usage = Map<String, dynamic>.from(m['model']);
          } else {
            usage = m;
          }
        }
        setState(() { _totalUsageData = usage; _isLoadingUsage = false; });
      } else if (_usagePeriod != 'all') {
        // إذا فشل period-usage، نرجع لـ total-usage
        debugPrint('[_fetchTotalUsage] period-usage failed, falling back to total-usage');
        _usagePeriod = 'all';
        _fetchTotalUsage();
        return;
      } else {
        setState(() => _isLoadingUsage = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingUsage = false);
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
    final screenH = MediaQuery.of(context).size.height;
    final double sc = (screenH / 900).clamp(0.75, 1.0);
    final color = accent ?? Colors.blueGrey;
    final bool isMobile = _isMobile(context);
    final double lblSize = labelFontSize ?? (isMobile ? 11.0 : 18 * sc);
    final double valSize = valueFontSize ?? (isMobile ? 12.0 : 18 * sc);
    final double iconSize = isMobile ? 14.0 : 20 * sc;
    final double vPad = isMobile ? 6.0 : 16 * sc;
    final double hPad = isMobile ? 6.0 : 10 * sc;
    return InputDecorator(
      decoration: InputDecoration(
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: iconSize, color: color),
            SizedBox(width: isMobile ? 3.0 : 4 * sc),
            Text(label,
                style: TextStyle(
                    fontSize: lblSize,
                    color: color,
                    fontWeight: FontWeight.w900)),
          ],
        ),
        floatingLabelBehavior: FloatingLabelBehavior.always,
        floatingLabelAlignment: FloatingLabelAlignment.center,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.black87, width: 1.5),
        ),
        filled: highlightBg,
        fillColor: highlightBg ? color.withValues(alpha: 0.08) : null,
        contentPadding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
        isDense: isMobile,
      ),
      child: Text(value,
          maxLines: valueMaxLines,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: valSize,
              fontWeight: FontWeight.w800,
              color: highlightBg ? color : null)),
    );
  }

  Widget _twoPerRowGrid(List<Widget> tiles) {
    if (tiles.isEmpty) return const SizedBox();
    final double width = MediaQuery.of(context).size.width;
    final screenH = MediaQuery.of(context).size.height;
    final double sc = (screenH / 900).clamp(0.75, 1.0);
    final bool isMobile = _isMobile(context);
    final double spacing = isMobile ? 6.0 : 12 * sc;

    // عدد الأعمدة حسب عرض الشاشة
    final int cols;
    if (width < 320) {
      cols = 1;
    } else if (width < 900) {
      cols = 2;
    } else {
      cols = 4;
    }

    final children = <Widget>[];
    for (int i = 0; i < tiles.length; i += cols) {
      final rowItems = <Widget>[];
      for (int j = 0; j < cols; j++) {
        if (j > 0) rowItems.add(SizedBox(width: spacing));
        rowItems.add(Expanded(
          child: (i + j < tiles.length) ? tiles[i + j] : const SizedBox(),
        ));
      }
      children.add(Row(children: rowItems));
      if (i + cols < tiles.length) children.add(SizedBox(height: spacing));
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
    final int valueLines = _isMobile(context) ? 2 : 1;

    tiles.add(_metricTile(
      isActive ? Icons.verified : Icons.error_outline,
      'الحالة',
      statusDisplay,
      accent: sc,
      highlightBg: true,
      valueMaxLines: valueLines,
    ));
    tiles.add(_metricTile(
      Icons.category,
      'الحزمة',
      _baseService(services),
      valueMaxLines: valueLines,
    ));
    if (fbg != null && fbg.isNotEmpty) {
      tiles.add(_metricTile(
        Icons.router,
        'FBG',
        fbg,
        valueMaxLines: valueLines,
      ));
    }
    if (fat != null && fat.isNotEmpty) {
      tiles.add(_metricTile(
        Icons.hub,
        'FAT',
        fat,
        valueMaxLines: valueLines,
      ));
    }
    if (startedAt != null && startedAt.isNotEmpty) {
      tiles.add(_metricTile(
        Icons.play_circle,
        'تاريخ البدء',
        _fmtDate(startedAt),
        valueMaxLines: valueLines,
      ));
    }
    tiles.add(_metricTile(
      Icons.event,
      'تاريخ الانتهاء',
      _fmtDateTime(endDate),
      valueMaxLines: valueLines,
    ));
    if (dur != null) {
      tiles.add(_metricTile(
        Icons.schedule,
        'مدة الاشتراك',
        '$dur يوم',
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
      highlightBg: true,
      valueMaxLines: valueLines,
    ));

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _twoPerRowGrid(tiles),
    ]);
  }

  Widget _deviceBox(Map<String, dynamic> dev) {
    final screenH = MediaQuery.of(context).size.height;
    final double sc = (screenH / 900).clamp(0.75, 1.0);
    final int valueLines = _isMobile(context) ? 2 : 1;

    final username = _safeGetString(dev['username']) ?? 'غير متوفر';
    final serial = _safeGetString(dev['serial']) ?? 'غير متوفر';
    final mac = _safeGetString(dev['macAddress']);

    // حقل السيريال مع زر تعديل
    final serialTile = Stack(
      children: [
        _metricTile(Icons.memory, 'السيريال', serial,
            accent: Colors.teal, valueMaxLines: valueLines),
        Positioned(
          left: 6 * sc,
          top: 0,
          bottom: 0,
          child: Center(
            child: Material(
              color: Colors.teal.shade700,
              shape: const CircleBorder(),
              elevation: 2,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => _showEditSerialDialog(serial),
                child: Padding(
                  padding: EdgeInsets.all(6 * sc),
                  child: Icon(Icons.edit, size: 22 * sc, color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      ],
    );

    final tiles = <Widget>[
      _metricTile(Icons.person, 'اليوزر نيم', username,
          accent: Colors.indigo, valueMaxLines: valueLines),
      serialTile,
      if (mac != null && mac.isNotEmpty)
        _metricTile(Icons.lan, 'MAC Address', mac,
            accent: Colors.deepPurple, valueMaxLines: valueLines),
    ];

    return _twoPerRowGrid(tiles);
  }

  /// معلومات الجهاز + حالة الجهاز + قوة الإشارة في شبكة واحدة
  Widget _deviceAndOntCombined(Map<String, dynamic>? deviceDetails) {
    final screenH = MediaQuery.of(context).size.height;
    final double sc = (screenH / 900).clamp(0.75, 1.0);
    final int valueLines = _isMobile(context) ? 2 : 1;

    final tiles = <Widget>[];

    // بيانات الجهاز (يوزر نيم + سيريال + MAC)
    if (deviceDetails != null) {
      final username = _safeGetString(deviceDetails['username']) ?? 'غير متوفر';
      final serial = _safeGetString(deviceDetails['serial']) ?? 'غير متوفر';
      final mac = _safeGetString(deviceDetails['macAddress']);

      tiles.add(_metricTile(Icons.person, 'اليوزر نيم', username,
          accent: Colors.indigo, valueMaxLines: valueLines));

      tiles.add(Stack(
        children: [
          _metricTile(Icons.memory, 'السيريال', serial,
              accent: Colors.teal, valueMaxLines: valueLines),
          Positioned(
            left: 6 * sc,
            top: 0,
            bottom: 0,
            child: Center(
              child: Material(
                color: Colors.teal.shade700,
                shape: const CircleBorder(),
                elevation: 2,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => _showEditSerialDialog(serial),
                  child: Padding(
                    padding: EdgeInsets.all(6 * sc),
                    child: Icon(Icons.edit, size: 22 * sc, color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
        ],
      ));

      if (mac != null && mac.isNotEmpty) {
        tiles.add(_metricTile(Icons.lan, 'MAC Address', mac,
            accent: Colors.deepPurple, valueMaxLines: valueLines));
      }

      // كلمة مرور الجهاز (PPPoE)
      final pass = _safeGetString(_deviceFullInfo?['devicePassword']);
      if (pass != null && pass.isNotEmpty) {
        tiles.add(_metricTile(Icons.vpn_key, 'كلمة المرور', pass,
            accent: Colors.red.shade700, valueMaxLines: valueLines));
      }
    }

    // حالة الجهاز + قوة الإشارة من ONT
    if (isLoadingOntInfo) {
      tiles.add(const Center(child: CircularProgressIndicator(strokeWidth: 2)));
    } else if (deviceOntInfo != null) {
      final model = _safeGetMap(deviceOntInfo!['model']);
      final status = _safeGetMap(model?['status']);
      final rxPower = model?['rxPower'];
      final rawStatusDisp = _safeGetString(status?['displayValue']);
      final statusVal = rawStatusDisp?.toLowerCase() ?? '';
      Color statusColor = Colors.grey;
      IconData statusIcon = Icons.device_unknown;
      if (statusVal == 'up') {
        statusColor = Colors.green;
        statusIcon = Icons.signal_wifi_4_bar;
      } else if (statusVal == 'down') {
        statusColor = Colors.red;
        statusIcon = Icons.signal_wifi_off;
      }
      final localizedStatus = _localizedDeviceStatus(rawStatusDisp);
      tiles.add(
          _statusTile(statusIcon, 'حالة الجهاز', localizedStatus, statusColor));

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
      tiles.add(_statusTile(null, 'قوة الإشارة',
          '${_safeGetString(rxPower) ?? 'غير معروف'} dBm', powerColor,
          badge: powerStatus));

      // موديل الجهاز
      final modelName = _safeGetString(model?['model']);
      if (modelName != null && modelName.isNotEmpty) {
        tiles.add(_metricTile(Icons.router, 'موديل الجهاز', modelName,
            accent: Colors.blueGrey, valueMaxLines: valueLines));
      }
    }

    // زر الدخول للراوتر
    {
      final ip = _safeGetString(_deviceFullInfo?['ipAddress']);
      final devicePass = _safeGetString(_deviceFullInfo?['devicePassword']);
      if (ip != null && ip.isNotEmpty) {
        tiles.add(_routerAccessTile(ip, devicePass));
      }
    }

    if (tiles.isEmpty && _totalUsageData == null && !_isLoadingUsage) {
      return _msgBox('لا توجد معلومات تقنية متاحة للجهاز', Colors.grey,
          Icons.info_outline);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (tiles.isNotEmpty) _twoPerRowGrid(tiles),
        // بلاطة حجم التحميل (عرض كامل مع فلتر فترة)
        if (_isLoadingUsage)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (_totalUsageData != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _usageTile(),
          ),
      ],
    );
  }

  String _fmtBytes(dynamic bytes) {
    if (bytes == null) return '0';
    final b = bytes is num
        ? bytes.toDouble()
        : double.tryParse(bytes.toString()) ?? 0;
    if (b >= 1073741824) return '${(b / 1073741824).toStringAsFixed(2)} GB';
    if (b >= 1048576) return '${(b / 1048576).toStringAsFixed(1)} MB';
    if (b >= 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '${b.toStringAsFixed(0)} B';
  }

  Widget _usageTile() {
    final u = _totalUsageData!;
    final dl = u['totalDownloadedBytes'] ?? u['download'] ?? u['totalDownload'];
    final ul = u['totalUploadedBytes'] ?? u['upload'] ?? u['totalUpload'];
    num dlNum = dl is num ? dl : (num.tryParse(dl?.toString() ?? '') ?? 0);
    num ulNum = ul is num ? ul : (num.tryParse(ul?.toString() ?? '') ?? 0);

    final periodLabel = _usagePeriod == 'today'
        ? 'اليوم'
        : _usagePeriod == 'month'
            ? 'هذا الشهر'
            : 'الكل';
    final isMobile = _isMobile(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // فلتر الفترة
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _periodChip('اليوم', 'today'),
            const SizedBox(width: 6),
            _periodChip('هذا الشهر', 'month'),
            const SizedBox(width: 6),
            _periodChip('الكل', 'all'),
          ],
        ),
        const SizedBox(height: 6),
        // بلاطات التحميل والرفع
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _showSessionsUsageDialog(),
          child: Row(
            children: [
              Expanded(
                child: _metricTile(Icons.cloud_download,
                    '↓ تحميل ($periodLabel)', _fmtBytes(dlNum),
                    accent: Colors.blue.shade700,
                    highlightBg: true,
                    valueMaxLines: isMobile ? 2 : 1),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _metricTile(Icons.cloud_upload, '↑ رفع ($periodLabel)',
                    _fmtBytes(ulNum),
                    accent: Colors.orange.shade700,
                    highlightBg: true,
                    valueMaxLines: isMobile ? 2 : 1),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _periodChip(String label, String value) {
    final selected = _usagePeriod == value;
    return GestureDetector(
      onTap: () {
        if (_usagePeriod != value) {
          setState(() => _usagePeriod = value);
          _fetchTotalUsage();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? Colors.blue.shade700 : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: selected ? Colors.blue.shade700 : Colors.grey.shade400),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : Colors.black87)),
      ),
    );
  }

  // ═══════ أزرار تعليق / إعادة تفعيل ═══════
  bool _isSuspending = false;
  bool _isUnsuspending = false;

  Widget _suspendUnsuspendButtons() {
    final screenH = MediaQuery.of(context).size.height;
    final double sc = (screenH / 900).clamp(0.75, 1.0);
    final isMobile = _isMobile(context);

    // تحديد حالة الاشتراك الحالية
    final statusRaw = subscriptionDetails?['status'];
    final statusStr = statusRaw is String
        ? statusRaw
        : _safeGetString((statusRaw as Map?)?['displayValue']) ?? '';
    final isActive = statusStr.toLowerCase() == 'active';
    final isSuspended = statusStr.toLowerCase() == 'suspended';

    return Row(
      children: [
        // زر تعليق
        if (isActive)
          Expanded(
            child: ElevatedButton.icon(
              icon: _isSuspending
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Icon(Icons.pause_circle_filled, size: 18 * sc),
              label: Text(_isSuspending ? 'جاري التعليق...' : 'تعليق الاشتراك',
                  style: TextStyle(
                      fontSize: (isMobile ? 13 : 14) * sc,
                      fontWeight: FontWeight.w800)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
                foregroundColor: Colors.white,
                padding:
                    EdgeInsets.symmetric(vertical: (isMobile ? 10 : 14) * sc),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _isSuspending ? null : () => _confirmSuspend(),
            ),
          ),
        // زر إعادة تفعيل
        if (isSuspended)
          Expanded(
            child: ElevatedButton.icon(
              icon: _isUnsuspending
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Icon(Icons.play_circle_filled, size: 18 * sc),
              label: Text(_isUnsuspending ? 'جاري التفعيل...' : 'إعادة تفعيل',
                  style: TextStyle(
                      fontSize: (isMobile ? 13 : 14) * sc,
                      fontWeight: FontWeight.w800)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                foregroundColor: Colors.white,
                padding:
                    EdgeInsets.symmetric(vertical: (isMobile ? 10 : 14) * sc),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _isUnsuspending ? null : () => _confirmUnsuspend(),
            ),
          ),
        // زر الجلسات والاستهلاك
        if (isActive || isSuspended) ...[
          SizedBox(width: 8 * sc),
          Expanded(
            child: ElevatedButton.icon(
              icon: Icon(Icons.data_usage, size: 18 * sc),
              label: Text('الجلسات والاستهلاك',
                  style: TextStyle(
                      fontSize: (isMobile ? 13 : 14) * sc,
                      fontWeight: FontWeight.w800)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo.shade600,
                foregroundColor: Colors.white,
                padding:
                    EdgeInsets.symmetric(vertical: (isMobile ? 10 : 14) * sc),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => _showSessionsUsageDialog(),
            ),
          ),
        ],
      ],
    );
  }

  void _confirmSuspend() {
    final id = _extractSubscriptionId(subscriptionDetails!);
    if (id == null || id.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            SizedBox(width: 8),
            Text('تأكيد التعليق',
                style: TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
        content: const Text(
            'هل أنت متأكد من تعليق هذا الاشتراك؟\nسيتم إيقاف خدمة الإنترنت عن المشترك مؤقتاً.',
            style: TextStyle(fontSize: 14)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
                foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              _suspendSubscription(id);
            },
            child: const Text('تعليق',
                style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  void _confirmUnsuspend() {
    final id = _extractSubscriptionId(subscriptionDetails!);
    if (id == null || id.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 28),
            SizedBox(width: 8),
            Text('تأكيد إعادة التفعيل',
                style: TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
        content: const Text(
            'هل تريد إعادة تفعيل هذا الاشتراك؟\nسيتم استئناف خدمة الإنترنت.',
            style: TextStyle(fontSize: 14)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              _unsuspendSubscription(id);
            },
            child: const Text('تفعيل',
                style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Future<void> _suspendSubscription(String id) async {
    setState(() => _isSuspending = true);
    try {
      final r = await AuthService.instance.authenticatedRequest(
          'POST', 'https://admin.ftth.iq/api/subscriptions/$id/suspend');
      if (!mounted) return;
      if (r.statusCode == 200 || r.statusCode == 204) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('تم تعليق الاشتراك بنجاح'),
            backgroundColor: Colors.orange));
        fetchUserDetailsAndSubscription();
      } else if (r.statusCode == 401) {
        AuthErrorHandler.handle401Error(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('فشل التعليق: ${r.statusCode} - ${r.body}'),
            backgroundColor: Colors.red));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isSuspending = false);
    }
  }

  Future<void> _unsuspendSubscription(String id) async {
    setState(() => _isUnsuspending = true);
    try {
      final r = await AuthService.instance.authenticatedRequest(
          'POST', 'https://admin.ftth.iq/api/subscriptions/$id/unsuspend');
      if (!mounted) return;
      if (r.statusCode == 200 || r.statusCode == 204) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('تم إعادة تفعيل الاشتراك بنجاح'),
            backgroundColor: Colors.green));
        fetchUserDetailsAndSubscription();
      } else if (r.statusCode == 401) {
        AuthErrorHandler.handle401Error(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('فشل التفعيل: ${r.statusCode} - ${r.body}'),
            backgroundColor: Colors.red));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isUnsuspending = false);
    }
  }

  // ═══════ شاشة الجلسات والاستهلاك ═══════
  void _showSessionsUsageDialog() {
    final id = _extractSubscriptionId(subscriptionDetails!);
    if (id == null || id.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => _SessionsUsageDialog(subscriptionId: id),
    );
  }

  Widget _routerAccessTile(String ip, String? devicePass) {
    final screenH = MediaQuery.of(context).size.height;
    final double sc = (screenH / 900).clamp(0.75, 1.0);
    final bool isMobile = _isMobile(context);
    final double iconSize = isMobile ? 14.0 : 20 * sc;
    final double lblSize = isMobile ? 11.0 : 18 * sc;
    final double vPad = isMobile ? 6.0 : 16 * sc;
    final double hPad = isMobile ? 6.0 : 10 * sc;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _showRouterAccessDialog(ip, devicePass),
      child: InputDecorator(
        decoration: InputDecoration(
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.open_in_browser,
                  size: iconSize, color: Colors.deepOrange),
              SizedBox(width: isMobile ? 3.0 : 4 * sc),
              Text('الدخول للراوتر',
                  style: TextStyle(
                      fontSize: lblSize,
                      color: Colors.deepOrange,
                      fontWeight: FontWeight.w900)),
            ],
          ),
          floatingLabelBehavior: FloatingLabelBehavior.always,
          floatingLabelAlignment: FloatingLabelAlignment.center,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.deepOrange, width: 1.5),
          ),
          filled: true,
          fillColor: Colors.deepOrange.withValues(alpha: 0.08),
          contentPadding:
              EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
          isDense: isMobile,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.router,
                size: (isMobile ? 14 : 18) * sc, color: Colors.deepOrange),
            SizedBox(width: 4 * sc),
            Text(ip,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: (isMobile ? 12.0 : 18 * sc),
                    fontWeight: FontWeight.w800,
                    color: Colors.deepOrange)),
          ],
        ),
      ),
    );
  }

  /// كشف نوع الـ IP: هل هو عام أم داخلي/CGNAT
  String? _getIpWarning(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return null;
    final a = int.tryParse(parts[0]) ?? 0;
    final b = int.tryParse(parts[1]) ?? 0;
    // CGNAT: 100.64.0.0 – 100.127.255.255
    if (a == 100 && b >= 64 && b <= 127) {
      return 'هذا IP من نوع CGNAT (داخلي لشبكة المزود) — يجب أن تكون متصلاً بشبكة FTTH الداخلية أو عبر VPN للوصول إليه';
    }
    // Private: 10.x.x.x
    if (a == 10) {
      return 'هذا IP خاص (Private) — يجب أن تكون متصلاً بنفس الشبكة المحلية للوصول إليه';
    }
    // Private: 172.16-31.x.x
    if (a == 172 && b >= 16 && b <= 31) {
      return 'هذا IP خاص (Private) — يجب أن تكون متصلاً بنفس الشبكة المحلية للوصول إليه';
    }
    // Private: 192.168.x.x
    if (a == 192 && b == 168) {
      return 'هذا IP خاص (Private) — يجب أن تكون متصلاً بنفس الشبكة المحلية للوصول إليه';
    }
    return null; // IP عام
  }

  void _showRouterAccessDialog(String ip, String? devicePass) {
    final ontModel =
        _safeGetString(_safeGetMap(deviceOntInfo?['model'])?['model']);

    final defaults = _getDefaultCredentials(ontModel);
    final ipWarning = _getIpWarning(ip);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.router, color: Colors.deepOrange),
            const SizedBox(width: 8),
            Expanded(
              child: Text('الدخول لجهاز الراوتر',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 18)),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // تنبيه نوع الـ IP
              if (ipWarning != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade300),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          size: 20, color: Colors.red.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(ipWarning,
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.red.shade800,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
              _dialogInfoRow('IP', ip, Icons.language),
              if (ontModel != null && ontModel.isNotEmpty)
                _dialogInfoRow('الموديل', ontModel, Icons.devices),
              const Divider(height: 24),
              const Text('بيانات الدخول الافتراضية:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              ...defaults.map((cred) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (cred['note'] != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(cred['note']!,
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey.shade600)),
                          ),
                        Row(
                          children: [
                            const Icon(Icons.person,
                                size: 16, color: Colors.blueGrey),
                            const SizedBox(width: 4),
                            const Text('User: ',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 13)),
                            Expanded(
                              child: SelectableText(cred['user']!,
                                  style: const TextStyle(
                                      fontSize: 13, fontFamily: 'monospace')),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy, size: 16),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () {
                                Clipboard.setData(
                                    ClipboardData(text: cred['user']!));
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                    const SnackBar(
                                        content: Text('تم النسخ'),
                                        duration: Duration(seconds: 1)));
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.lock,
                                size: 16, color: Colors.blueGrey),
                            const SizedBox(width: 4),
                            const Text('Pass: ',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 13)),
                            Expanded(
                              child: SelectableText(cred['pass']!,
                                  style: const TextStyle(
                                      fontSize: 13, fontFamily: 'monospace')),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy, size: 16),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () {
                                Clipboard.setData(
                                    ClipboardData(text: cred['pass']!));
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                    const SnackBar(
                                        content: Text('تم النسخ'),
                                        duration: Duration(seconds: 1)));
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  )),
              if (devicePass != null && devicePass.isNotEmpty) ...[
                const Divider(height: 24),
                _dialogInfoRow('كلمة مرور PPPoE', devicePass, Icons.vpn_key),
              ],
              const SizedBox(height: 8),
              Text(
                  'ملاحظة: كلمة مرور PPPoE تختلف عن كلمة مرور لوحة تحكم الراوتر',
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.orange.shade800,
                      fontStyle: FontStyle.italic)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.open_in_browser, size: 18),
            label:
                Text(ipWarning != null ? 'فتح (يحتاج VPN)' : 'فتح في المتصفح'),
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  ipWarning != null ? Colors.grey : Colors.deepOrange,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final url = Uri.parse('http://$ip');
              launchUrl(url, mode: LaunchMode.externalApplication);
            },
          ),
        ],
      ),
    );
  }

  Widget _dialogInfoRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.blueGrey),
          const SizedBox(width: 6),
          Text('$label: ',
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          Expanded(
            child: SelectableText(value,
                style: const TextStyle(fontSize: 13, fontFamily: 'monospace')),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 16),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('تم النسخ'), duration: Duration(seconds: 1)));
              }
            },
          ),
        ],
      ),
    );
  }

  List<Map<String, String>> _getDefaultCredentials(String? model) {
    final m = (model ?? '').toLowerCase();
    if (m.contains('huawei') ||
        m.contains('hg8') ||
        m.contains('eg8') ||
        m.contains('hw')) {
      return [
        {'user': 'root', 'pass': 'adminHW', 'note': 'Huawei - الأكثر شيوعاً'},
        {
          'user': 'telecomadmin',
          'pass': 'admintelecom',
          'note': 'Huawei - بديل'
        },
      ];
    } else if (m.contains('zte') || m.contains('f6') || m.contains('f67')) {
      return [
        {'user': 'admin', 'pass': 'admin', 'note': 'ZTE - افتراضي'},
        {'user': 'user', 'pass': 'user', 'note': 'ZTE - مستخدم عادي'},
      ];
    } else if (m.contains('nokia') ||
        m.contains('g-240') ||
        m.contains('alcatel')) {
      return [
        {'user': 'admin', 'pass': '1234', 'note': 'Nokia/Alcatel - افتراضي'},
      ];
    } else if (m.contains('tp-link') || m.contains('tplink')) {
      return [
        {'user': 'admin', 'pass': 'admin', 'note': 'TP-Link - افتراضي'},
      ];
    } else if (m.contains('vsol') || m.contains('v-sol')) {
      return [
        {'user': 'admin', 'pass': 'stdONUi0', 'note': 'VSOL - افتراضي'},
        {'user': 'admin', 'pass': 'admin', 'note': 'VSOL - بديل'},
      ];
    }
    // افتراضي عام
    return [
      {'user': 'admin', 'pass': 'admin', 'note': 'افتراضي عام'},
      {'user': 'root', 'pass': 'admin', 'note': 'بديل شائع'},
    ];
  }

  // ═══════ فحص حالة ربط GenieACS (في الخلفية) ═══════
  Future<void> _checkGenieAcsStatus() async {
    try {
      // ننتظر حتى تتوفر بيانات الاشتراك
      await Future.delayed(const Duration(seconds: 2));
      final deviceDetails = _safeGetMap(subscriptionDetails?['deviceDetails']);
      final username = _safeGetString(deviceDetails?['username']);
      if (username == null || username.trim().isEmpty) {
        if (mounted) setState(() => _genieAcsLinked = false);
        return;
      }
      final raw = await GenieAcsService.instance.findDevice(
        pppoeUsername: username.trim(),
        serial: _safeGetString(deviceDetails?['serial']),
        mac: _safeGetString(deviceDetails?['macAddress']),
      );
      if (mounted) setState(() => _genieAcsLinked = raw != null);
    } catch (_) {
      if (mounted) setState(() => _genieAcsLinked = false);
    }
  }

  // ═══════ زر تحكم بالراوتر عن بعد (GenieACS) ═══════
  Widget _genieAcsButton() {
    final deviceDetails = _safeGetMap(subscriptionDetails?['deviceDetails']);
    final username = _safeGetString(deviceDetails?['username']);
    if (username == null || username.trim().isEmpty) return const SizedBox.shrink();

    final screenH = MediaQuery.of(context).size.height;
    final double sc = (screenH / 900).clamp(0.75, 1.0);
    final isMobile = _isMobile(context);

    final linked = _genieAcsLinked;
    final statusIcon = linked == null
        ? SizedBox(width: 14 * sc, height: 14 * sc, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70))
        : Icon(Icons.circle, size: 12 * sc, color: linked ? Colors.greenAccent : Colors.redAccent);
    final statusText = linked == null ? '' : (linked ? '  متصل' : '  غير مرتبط');

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        icon: Icon(Icons.settings_remote, size: 20 * sc),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('تحكم بالراوتر عن بعد',
                style: TextStyle(fontSize: (isMobile ? 13 : 15) * sc, fontWeight: FontWeight.w800)),
            SizedBox(width: 8 * sc),
            statusIcon,
            if (statusText.isNotEmpty)
              Text(statusText, style: TextStyle(fontSize: 11 * sc, fontWeight: FontWeight.w600)),
          ],
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: linked == false ? Colors.grey.shade600 : Colors.teal.shade700,
          foregroundColor: Colors.white,
          padding: EdgeInsets.symmetric(vertical: (isMobile ? 10 : 14) * sc),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onPressed: () {
          showDialog(
            context: context,
            builder: (_) => _RouterManagementDialog(
              pppoeUsername: username.trim(),
              serial: _safeGetString(deviceDetails?['serial']),
              mac: _safeGetString(deviceDetails?['macAddress']),
            ),
          );
        },
      ),
    );
  }

  void _showEditSerialDialog(String currentSerial) {
    if (subscriptionDetails == null) return;
    final id = _extractSubscriptionId(subscriptionDetails!);
    if (id == null || id.isEmpty) return;
    final dev = _safeGetMap(subscriptionDetails!['deviceDetails']);
    final username = _safeGetString(dev?['username']) ?? '';
    final mac = _safeGetString(dev?['macAddress']) ?? '';
    final controller = TextEditingController(text: currentSerial);

    showDialog(
      context: context,
      builder: (ctx) {
        bool saving = false;
        String? error;
        return StatefulBuilder(builder: (ctx, setDialogState) {
          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: const Row(
              children: [
                Icon(Icons.memory, color: Colors.teal),
                SizedBox(width: 8),
                Text('تعديل السيريال',
                    style: TextStyle(fontWeight: FontWeight.w800)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    labelText: 'السيريال الجديد',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    prefixIcon: const Icon(Icons.memory),
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!,
                      style: TextStyle(
                          color: error!.contains('نجاح')
                              ? Colors.green
                              : Colors.red,
                          fontWeight: FontWeight.w800)),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(ctx),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: saving
                    ? null
                    : () async {
                        final newSerial = controller.text.trim();
                        if (newSerial.isEmpty) {
                          setDialogState(() => error = 'أدخل السيريال');
                          return;
                        }
                        setDialogState(() {
                          saving = true;
                          error = null;
                        });
                        try {
                          final r = await AuthService.instance.authenticatedRequest(
                              'PUT',
                              'https://admin.ftth.iq/api/subscriptions/$id/device',
                              body: jsonEncode({
                                'username': username,
                                'ontSerial': newSerial,
                                'macAddress': mac,
                              }));
                          if (!ctx.mounted) return;
                          if (r.statusCode == 200) {
                            setDialogState(() => error = 'تم التحديث بنجاح');
                            Future.delayed(const Duration(seconds: 1), () {
                              if (ctx.mounted) Navigator.pop(ctx);
                              fetchUserDetailsAndSubscription();
                            });
                          } else if (r.statusCode == 401) {
                            if (mounted)
                              AuthErrorHandler.handle401Error(context);
                            return;
                          } else {
                            setDialogState(
                                () => error = 'فشل: ${r.statusCode}');
                          }
                        } catch (e) {
                          if (ctx.mounted) setDialogState(() => error = 'خطأ');
                        } finally {
                          if (ctx.mounted) setDialogState(() => saving = false);
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                ),
                child: saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('حفظ',
                        style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          );
        });
      },
    );
  }

  /// زر تعديل الجهاز (يُعرض أسفل قسم حالة الجهاز وقوة الإشارة)
  Widget _editDeviceButton() {
    if (subscriptionDetails == null) return const SizedBox();
    final dev = _safeGetMap(subscriptionDetails!['deviceDetails']);
    if (dev == null) return const SizedBox();
    final username = _safeGetString(dev['username']) ?? '';
    final serial = _safeGetString(dev['serial']) ?? '';
    final mac = _safeGetString(dev['macAddress']) ?? '';
    final screenH = MediaQuery.of(context).size.height;
    final double sc = (screenH / 900).clamp(0.75, 1.0);
    return Padding(
      padding: EdgeInsets.only(top: 8 * sc),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () {
            final id = _extractSubscriptionId(subscriptionDetails!);
            if (id == null || id.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('لا يمكن العثور على معرف الاشتراك'),
                  backgroundColor: Colors.red));
              return;
            }
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
          label: const Text('تعديل الجهاز'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            textStyle:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
    );
  }

  Widget _sessionBox(Map<String, dynamic> s) {
    final screenH = MediaQuery.of(context).size.height;
    final double sc = (screenH / 900).clamp(0.75, 1.0);
    final totalSecs =
        int.tryParse(_safeGetString(s['sessionTimeInSeconds']) ?? '0') ?? 0;

    String durationHuman = 'أقل من دقيقة';
    if (totalSecs > 0) {
      final days = totalSecs ~/ 86400;
      final hours = (totalSecs % 86400) ~/ 3600;
      final mins = (totalSecs % 3600) ~/ 60;
      final parts = <String>[];
      if (days > 0) parts.add('$days يوم');
      if (hours > 0) parts.add('$hours ساعة');
      if (mins > 0) parts.add('$mins دقيقة');
      if (parts.isNotEmpty) durationHuman = parts.join(' و ');
    }

    return _statusTile(
        Icons.wifi, 'نشط منذ', durationHuman, Colors.green.shade700);
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
    ]);
  }

  Widget _statusTile(IconData? icon, String label, String value, Color c,
      {String? badge}) {
    final screenH = MediaQuery.of(context).size.height;
    final double sc = (screenH / 900).clamp(0.75, 1.0);
    return InputDecorator(
      decoration: InputDecoration(
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, color: c, size: 20 * sc),
              SizedBox(width: 4 * sc),
            ],
            Text(label,
                style: TextStyle(
                    fontSize: 18 * sc, color: c, fontWeight: FontWeight.w900)),
          ],
        ),
        floatingLabelBehavior: FloatingLabelBehavior.always,
        floatingLabelAlignment: FloatingLabelAlignment.center,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: c, width: 1.5),
        ),
        filled: true,
        fillColor: c.withValues(alpha: 0.08),
        contentPadding:
            EdgeInsets.symmetric(horizontal: 10 * sc, vertical: 16 * sc),
        isDense: false,
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(value,
            style: TextStyle(
                fontSize: 18 * sc, fontWeight: FontWeight.w800, color: c)),
        if (badge != null && badge.isNotEmpty) ...[
          SizedBox(width: 12 * sc),
          Container(
              padding:
                  EdgeInsets.symmetric(horizontal: 8 * sc, vertical: 3 * sc),
              decoration: BoxDecoration(
                  color: c.withValues(alpha: .2),
                  borderRadius: BorderRadius.circular(12)),
              child: Text(badge,
                  style: TextStyle(
                      fontSize: 11 * sc,
                      fontWeight: FontWeight.bold,
                      color: c)))
        ]
      ]),
    );
  }

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
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
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
      _showErrorDialog('حدث خطأ أثناء تحميل البيانات');
    }
  }

  Future<Map<String, dynamic>?> _fetchCustomerDetails() async {
    try {
      final r = await AuthService.instance.authenticatedRequest(
          'GET', 'https://admin.ftth.iq/api/customers/${widget.userId}');
      debugPrint('📞 [fetchCustomerDetails] status=${r.statusCode}');
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body);
        debugPrint(
            '📞 [fetchCustomerDetails] keys=${data is Map<String, dynamic> ? data.keys.toList() : "NOT_MAP"}');
        if (data is Map<String, dynamic>) {
          final model = data['model'];
          debugPrint(
              '📞 [fetchCustomerDetails] model keys=${model is Map<String, dynamic> ? model.keys.toList() : "NO_MODEL"}');
          if (model is Map<String, dynamic>) {
            debugPrint(
                '📞 [fetchCustomerDetails] primaryContact=${model['primaryContact']}');
            return model;
          }
          debugPrint(
              '📞 [fetchCustomerDetails] primaryContact=${data['primaryContact']}');
          return data;
        }
      } else if (r.statusCode == 401) {
        if (mounted) AuthErrorHandler.handle401Error(context);
        return null;
      } else {
        debugPrint(
            '📞 [fetchCustomerDetails] body=${r.body.substring(0, r.body.length.clamp(0, 200))}');
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
                    fontWeight: FontWeight.w800,
                    color: Colors.grey.shade700,
                    fontSize: 14))),
        const SizedBox(width: 8),
        Expanded(
            flex: 3,
            child: Text(value,
                style: const TextStyle(
                    fontSize: 14,
                    color: Colors.black87,
                    fontWeight: FontWeight.w800),
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

  Widget _buildPhoneTile(
      double width, Color? tileBg, Color? tileBorder, Color? iconBg) {
    final screenH = MediaQuery.of(context).size.height;
    final double sc = (screenH / 900).clamp(0.75, 1.0);
    return SizedBox(
      width: width,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 8 * sc, vertical: 6 * sc),
        decoration: BoxDecoration(
          color: tileBg ?? Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: tileBorder ?? Colors.grey.shade200),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(4 * sc),
              decoration: BoxDecoration(
                  color: iconBg ?? Colors.green.shade100,
                  borderRadius: BorderRadius.circular(6)),
              child: Icon(Icons.phone,
                  size: 14 * sc, color: Colors.green.shade700),
            ),
            SizedBox(width: 8 * sc),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('رقم الهاتف',
                      style: TextStyle(
                          fontSize: 11 * sc,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w800)),
                  if (_resolvedPhone.isNotEmpty)
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(
                        _fmtPhoneLocal(_resolvedPhone),
                        style: TextStyle(
                            fontSize: 13 * sc,
                            color: Colors.black87,
                            fontWeight: FontWeight.w800),
                      ),
                    )
                  else
                    Text('غير متوفر',
                        style: TextStyle(
                            fontSize: 12 * sc, color: Colors.grey.shade500)),
                ],
              ),
            ),
            if (_resolvedPhone.isNotEmpty)
              Tooltip(
                message: 'نسخ رقم الهاتف',
                child: IconButton(
                  icon: Icon(Icons.copy_rounded,
                      size: 18 * sc, color: Colors.green.shade700),
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
                  icon:
                      Icon(Icons.search, size: 16, color: Colors.blue.shade700),
                  label: Text('إظهار الرقم',
                      style:
                          TextStyle(fontSize: 12, color: Colors.blue.shade700)),
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
    final screenH = MediaQuery.of(context).size.height;
    final double sc = (screenH / 900).clamp(0.75, 1.0);
    return SizedBox(
      width: width,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 8 * sc, vertical: 6 * sc),
        decoration: BoxDecoration(
          color: backgroundColor ?? Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor ?? Colors.grey.shade200),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(4 * sc),
              decoration: BoxDecoration(
                  color: iconBgColor ?? Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(6)),
              child: Icon(icon, size: 14 * sc, color: Colors.blue.shade700),
            ),
            SizedBox(width: 8 * sc),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 11 * sc,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w800)),
                  Builder(
                    builder: (_) {
                      final valWidget = ltr
                          ? Directionality(
                              textDirection: TextDirection.ltr,
                              child: Text(value,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 13 * sc,
                                      color: Colors.black87,
                                      fontWeight: FontWeight.w800)))
                          : Text(value,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 13 * sc,
                                  color: Colors.black87,
                                  fontWeight: FontWeight.w800));
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
                  icon: Icon(Icons.copy_rounded, size: 22 * sc),
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

  void _copyAllVisibleInfo() {
    final lines = <String>[];
    lines.add('الاسم: ${widget.userName}');
    if (_resolvedPhone.isNotEmpty) {
      lines.add('رقم الهاتف: ${_fmtPhoneLocal(_resolvedPhone)}');
    }
    lines.add('معرف المستخدم: ${widget.userId}');
    if (subscriptionDetails != null) {
      final statusRaw = subscriptionDetails!['status'];
      final statusTxt = statusRaw is String
          ? statusRaw
          : _safeGetString(statusRaw?['displayValue']) ?? '';
      final normStatus = statusTxt.toString().trim().toLowerCase();
      final bool isActive = (normStatus == 'active' || normStatus == 'متصل');
      lines.add('الحالة: ${isActive ? "فعال" : "غير فعال"}');
      final services = _safeGetList(subscriptionDetails!['services']);
      lines.add('الحزمة: ${_baseService(services)}');
      final fbgFat = _getFbgFat();
      if (fbgFat.$1 != null && fbgFat.$1!.isNotEmpty)
        lines.add('FBG: ${fbgFat.$1}');
      if (fbgFat.$2 != null && fbgFat.$2!.isNotEmpty)
        lines.add('FAT: ${fbgFat.$2}');
      final startedAt = _safeGetString(subscriptionDetails!['startedAt']) ??
          _safeGetString(subscriptionDetails!['startDate']);
      if (startedAt != null) lines.add('تاريخ البدء: ${_fmtDate(startedAt)}');
      final endDate = _safeGetString(subscriptionDetails!['endDate']) ??
          _safeGetString(subscriptionDetails!['expires']);
      if (endDate != null)
        lines.add('تاريخ الانتهاء: ${_fmtDateTime(endDate)}');
      final d = _days(endDate);
      if (d > 0) {
        lines.add('الأيام المتبقية: $d يوم');
      } else if (d < 0) {
        lines.add('منتهي منذ: ${d.abs()} يوم');
      }
      final dev = _safeGetMap(subscriptionDetails!['deviceDetails']);
      if (dev != null) {
        final username = _safeGetString(dev['username']);
        if (username != null) lines.add('اليوز نيم: $username');
        final serial = _safeGetString(dev['serial']);
        if (serial != null) lines.add('Serial: $serial');
      }
    }
    final coords = _extractCoordinates(_customerDataMain);
    if (coords != null) lines.add('الموقع: ${coords.$1},${coords.$2}');
    Clipboard.setData(ClipboardData(text: lines.join('\n')));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('تم نسخ كل المعلومات'),
      backgroundColor: Colors.teal,
      duration: Duration(seconds: 2),
    ));
  }

  void _reloadAll() {
    fetchUserDetailsAndSubscription();
    _fetchAndStoreCustomerDetails();
  }

  /// صف واحد يحتوي الاسم + الهاتف + المعرف (3 حقول في صف)
  Widget _userInfoRow() {
    final screenH = MediaQuery.of(context).size.height;
    final double sc = (screenH / 900).clamp(0.75, 1.0);
    final bool isMobile = _isMobile(context);
    final double lblSize = isMobile ? 11.0 : 18 * sc;
    final double valSize = isMobile ? 12.0 : 18 * sc;
    final double iconSize = isMobile ? 14.0 : 20 * sc;
    final double vPad = isMobile ? 6.0 : 16 * sc;
    final double hPad = isMobile ? 6.0 : 10 * sc;

    Widget tile(IconData icon, String label, String value, Color accent,
        {Widget? trailing}) {
      return Expanded(
        child: InputDecorator(
          decoration: InputDecoration(
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: iconSize, color: accent),
                SizedBox(width: isMobile ? 3.0 : 5 * sc),
                Text(label,
                    style: TextStyle(
                        fontSize: lblSize,
                        color: accent,
                        fontWeight: FontWeight.w900)),
              ],
            ),
            floatingLabelBehavior: FloatingLabelBehavior.always,
            floatingLabelAlignment: FloatingLabelAlignment.center,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Colors.black87, width: 1.5),
            ),
            contentPadding:
                EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
            isDense: isMobile,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: valSize, fontWeight: FontWeight.w800)),
              ),
              if (trailing != null) trailing,
            ],
          ),
        ),
      );
    }

    Widget copyBtn(String data, String msg, Color color) {
      return Tooltip(
        message: msg,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () {
            Clipboard.setData(ClipboardData(text: data));
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(msg),
                backgroundColor: color,
                duration: const Duration(seconds: 2)));
          },
          child: Padding(
            padding: EdgeInsets.all(4 * sc),
            child: Icon(Icons.copy_rounded, size: 16 * sc, color: color),
          ),
        ),
      );
    }

    final phone = _resolvedPhone.isNotEmpty
        ? _fmtPhoneLocal(_resolvedPhone)
        : 'غير متوفر';
    final screenW = MediaQuery.of(context).size.width;
    final bool useColumn = screenW < 500;

    final nameTile = tile(
        Icons.person, 'الاسم', widget.userName, Colors.blue.shade700,
        trailing: copyBtn(widget.userName, 'تم نسخ الاسم', Colors.blue));
    final phoneTile = tile(
        Icons.phone, 'رقم الهاتف', phone, Colors.green.shade700,
        trailing: _resolvedPhone.isNotEmpty
            ? copyBtn(
                _fmtPhoneLocal(_resolvedPhone), 'تم نسخ الرقم', Colors.green)
            : (_isFetchingPhone
                ? SizedBox(
                    width: 16 * sc,
                    height: 16 * sc,
                    child: const CircularProgressIndicator(strokeWidth: 2))
                : Tooltip(
                    message: 'جلب الرقم',
                    child: InkWell(
                      onTap: _fetchPhoneManually,
                      child: Padding(
                        padding: EdgeInsets.all(4 * sc),
                        child: Icon(Icons.search,
                            size: 16 * sc, color: Colors.blue.shade700),
                      ),
                    ),
                  )));
    final idTile = tile(Icons.badge, 'المعرف', widget.userId, Colors.indigo,
        trailing: copyBtn(widget.userId, 'تم نسخ المعرف', Colors.indigo));

    if (useColumn) {
      return Column(
        children: [
          Row(children: [nameTile]),
          const SizedBox(height: 8),
          Row(children: [phoneTile, const SizedBox(width: 8), idTile]),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        nameTile,
        SizedBox(width: 12 * sc),
        phoneTile,
        SizedBox(width: 12 * sc),
        idTile,
      ],
    );
  }

  Widget _userNameRow() {
    final screenH = MediaQuery.of(context).size.height;
    final double sc = (screenH / 900).clamp(0.75, 1.0);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8 * sc, vertical: 6 * sc),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(4 * sc),
            decoration: BoxDecoration(
                color: Colors.blue.shade100,
                borderRadius: BorderRadius.circular(6)),
            child:
                Icon(Icons.person, size: 14 * sc, color: Colors.blue.shade700),
          ),
          SizedBox(width: 8 * sc),
          Expanded(
            child: Text(
              widget.userName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14 * sc, fontWeight: FontWeight.w700),
            ),
          ),
          // زر نسخ الاسم
          Tooltip(
            message: 'نسخ الاسم',
            child: IconButton(
              icon: Icon(Icons.copy_rounded,
                  size: 16 * sc, color: Colors.blue.shade700),
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
                icon: Icon(Icons.contact_page_rounded,
                    size: 16 * sc, color: Colors.teal.shade700),
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
        final r = await AuthService.instance.authenticatedRequest('GET', url);
        if (r.statusCode == 200) {
          try {
            return jsonDecode(r.body) as Map<String, dynamic>;
          } catch (_) {
            return null;
          }
        } else if (r.statusCode == 401) {
          if (mounted) AuthErrorHandler.handle401Error(context);
          return null;
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
      debugPrint('⚠️ فشل التحضير المسبق للتجديد');
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
    debugPrint('🔐 isAdminFlag: ${widget.isAdminFlag}');
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
                  isAdminFlag: widget.isAdminFlag,
                  firstSystemDepartment: widget.firstSystemDepartment,
                  firstSystemCenter: widget.firstSystemCenter,
                  firstSystemSalary: widget.firstSystemSalary,
                  ftthPermissions: widget.ftthPermissions,
                  userRoleHeader: widget.userRoleHeader,
                  clientAppHeader: widget.clientAppHeader,
                  taskAgentName: widget.taskAgentName,
                  taskAgentCode: widget.taskAgentCode,
                  taskNotes: widget.taskNotes,
                  taskId: widget.taskId,
                  taskServiceType: widget.taskServiceType,
                  taskDuration: widget.taskDuration,
                  taskAmount: widget.taskAmount,
                ))).then((_) {
      // تحديث بعد العودة
      fetchUserDetailsAndSubscription();
    });
  }

  // ═══════ بانر حالة التحصيل ═══════
  Widget _collectionBanner() {
    if (_isLoadingCollectionTasks || _collectionTasks.isEmpty)
      return const SizedBox.shrink();

    // فحص آخر طلب تحصيل
    final task = _collectionTasks.first;
    final details = task['details'] is String ? task['details'] as String : '';
    final status = task['status']?.toString().toLowerCase() ?? '';
    final techName = task['technician']?['fullName']?.toString() ??
        task['technicianName']?.toString() ??
        '';
    final taskId = task['id']?.toString() ?? '';
    final createdAt = task['createdAt']?.toString() ?? '';

    // استخراج المبلغ من Details
    final amountMatch = RegExp(r'تحصيل\s+([\d,]+)').firstMatch(details);
    final amountStr = amountMatch?.group(1) ?? '';

    final isCompleted = status == 'completed' || status == 'مكتملة';
    final isPending = status == 'pending' ||
        status == 'مفتوحة' ||
        status == 'inprogress' ||
        status == 'قيد التنفيذ';

    if (!isPending && !isCompleted) return const SizedBox.shrink();

    final isMobile = _isMobile(context);
    final smallFs = isMobile ? 11.0 : 12.0;
    final titleFs = isMobile ? 12.0 : 14.0;

    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: isMobile ? 6 : 8),
      padding: EdgeInsets.all(isMobile ? 8 : 12),
      decoration: BoxDecoration(
        color: isCompleted ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(isMobile ? 8 : 10),
        border: Border.all(
            color: isCompleted ? Colors.green.shade300 : Colors.orange.shade300,
            width: 1.2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(
            isCompleted ? Icons.check_circle : Icons.schedule,
            color: isCompleted ? Colors.green.shade700 : Colors.orange.shade700,
            size: isMobile ? 18 : 22,
          ),
          SizedBox(width: isMobile ? 6 : 8),
          Expanded(
            child: Text(
              isCompleted
                  ? 'تم التحصيل — جاهز للتجديد'
                  : 'طلب تحصيل قيد الانتظار',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: titleFs,
                color: isCompleted
                    ? Colors.green.shade800
                    : Colors.orange.shade800,
              ),
            ),
          ),
        ]),
        SizedBox(height: isMobile ? 4 : 6),
        if (techName.isNotEmpty)
          Text('الفني: $techName',
              style: TextStyle(fontSize: smallFs, color: Colors.grey.shade700)),
        if (amountStr.isNotEmpty)
          Text('المبلغ: $amountStr د.ع',
              style: TextStyle(fontSize: smallFs, color: Colors.grey.shade700)),
        if (createdAt.isNotEmpty)
          Text('التاريخ: ${_formatDate(createdAt)}',
              style: TextStyle(fontSize: smallFs, color: Colors.grey.shade700)),
        if (isCompleted) ...[
          SizedBox(height: isMobile ? 6 : 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _onRenewPressed,
              icon: Icon(Icons.refresh, size: isMobile ? 16 : 18),
              label: Text('تجديد الاشتراك الآن',
                  style: TextStyle(fontSize: isMobile ? 12 : 14)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade600,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: isMobile ? 8 : 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ]),
    );
  }

  String _formatDate(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate);
      return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return isoDate;
    }
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
    final screenH = MediaQuery.of(context).size.height;
    final double sc = (screenH / 900).clamp(0.75, 1.0);
    final double s = sc;
    final bool isMobileLayout = _isMobile(context);
    final pad = isMobileLayout ? 8.0 : 10.0 * sc;
    final gap = isMobileLayout ? 6.0 : 10.0 * sc;
    final cardGap = isMobileLayout ? 6.0 : 8.0 * sc;
    final titleSize = isMobileLayout ? 13.0 : 15.0 * sc;
    final coords = _extractCoordinates(_customerDataMain);
    final deviceDetails = subscriptionDetails == null
        ? null
        : _safeGetMap(subscriptionDetails!['deviceDetails']);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 52 * sc,
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        title: Text('تفاصيل المستخدم',
            style: _TextStyles.appBarTitle.copyWith(
                fontSize: 17 * sc,
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
              margin:
                  EdgeInsets.symmetric(horizontal: 4 * sc, vertical: 6 * sc),
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10)),
              child: IconButton(
                icon: Icon(Icons.arrow_back_ios_new,
                    size: 22 * sc, color: Colors.white),
                padding: EdgeInsets.all(8 * sc),
                constraints:
                    BoxConstraints(minWidth: 44 * sc, minHeight: 44 * sc),
                onPressed: () => Navigator.of(ctx).pop(),
                tooltip: 'رجوع',
              ),
            );
          },
        ),
        actions: [
          // زر إعادة التحميل
          Tooltip(
            message: 'إعادة تحميل',
            child: Container(
              margin:
                  EdgeInsets.symmetric(horizontal: 2 * sc, vertical: 6 * sc),
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10)),
              child: IconButton(
                icon: Icon(Icons.refresh, size: 20 * sc, color: Colors.white),
                padding: EdgeInsets.all(6 * sc),
                constraints:
                    BoxConstraints(minWidth: 36 * sc, minHeight: 36 * sc),
                onPressed: _reloadAll,
              ),
            ),
          ),
          // زر نسخ كل المعلومات
          Tooltip(
            message: 'نسخ كل المعلومات',
            child: Container(
              margin:
                  EdgeInsets.symmetric(horizontal: 2 * sc, vertical: 6 * sc),
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10)),
              child: IconButton(
                icon: Icon(Icons.copy_all, size: 20 * sc, color: Colors.amber),
                padding: EdgeInsets.all(6 * sc),
                constraints:
                    BoxConstraints(minWidth: 36 * sc, minHeight: 36 * sc),
                onPressed: _copyAllVisibleInfo,
              ),
            ),
          ),
          if (_canAddTask)
            Tooltip(
              message: 'إضافة مهمة',
              child: Container(
                margin:
                    EdgeInsets.symmetric(horizontal: 4 * sc, vertical: 6 * sc),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00B86B), Color(0xFF00894F)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x8800B86B),
                        blurRadius: 8,
                        offset: Offset(0, 2)),
                  ],
                  border: Border.all(color: Color(0xAAFFFFFF), width: 1.2),
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: _openAddTaskDialog,
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: 12 * sc, vertical: 6 * sc),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_task,
                              size: 22 * sc, color: Colors.white),
                          SizedBox(width: 4 * sc),
                          Text('مهمة',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14 * sc,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5)),
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
                margin:
                    EdgeInsets.symmetric(horizontal: 4 * sc, vertical: 6 * sc),
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10)),
                child: IconButton(
                  icon: Icon(Icons.menu, size: 22 * sc, color: Colors.white),
                  padding: EdgeInsets.all(8 * sc),
                  constraints:
                      BoxConstraints(minWidth: 44 * sc, minHeight: 44 * sc),
                  onPressed: () => Scaffold.of(ctx).openEndDrawer(),
                ),
              ),
            ),
          ),
        ],
      ),
      endDrawer: _sideMenu(),
      body: isLoading
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
                        elevation: 4,
                        shadowColor: Colors.blue.shade200,
                        color: Colors.blue.shade100.withValues(alpha: 0.8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: const BorderSide(
                                color: Colors.black87, width: 1.5)),
                        child: Padding(
                          padding: EdgeInsets.all(pad),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // هيدر البطاقة مع زر نسخ الكل
                              Row(
                                children: [
                                  Icon(Icons.person_outline,
                                      size: 15 * sc,
                                      color: Colors.blue.shade800),
                                  SizedBox(width: 4 * sc),
                                  Text('معلومات المستخدم',
                                      style: TextStyle(
                                          fontSize: 12 * sc,
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
                                        final fbgFat = _getFbgFat();
                                        final fbg = fbgFat.$1 ?? '';
                                        final fat = fbgFat.$2 ?? '';
                                        final services = subscriptionDetails !=
                                                null
                                            ? _safeGetList(subscriptionDetails![
                                                'services'])
                                            : null;
                                        final bundle = _baseService(services);
                                        final parts = <String>[
                                          'الاسم: ${widget.userName}',
                                          'رقم الهاتف: $phone',
                                        ];
                                        if (fbg.isNotEmpty)
                                          parts.add('FBG: $fbg');
                                        if (fat.isNotEmpty)
                                          parts.add('FAT: $fat');
                                        parts.add('الحزمة: $bundle');
                                        final text = parts.join('\n');
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
                                        padding: EdgeInsets.symmetric(
                                            horizontal: 8 * sc,
                                            vertical: 3 * sc),
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
                                                size: 12 * sc,
                                                color: Colors.teal.shade700),
                                            SizedBox(width: 3 * sc),
                                            Text('نسخ الكل',
                                                style: TextStyle(
                                                    fontSize: 11 * sc,
                                                    color: Colors.teal.shade700,
                                                    fontWeight:
                                                        FontWeight.w800)),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: gap),
                              _userInfoRow(),
                              SizedBox(height: gap),
                              _collectionBanner(),
                              _renewButton(context, fullWidth: true),
                              if (subscriptionDetails != null) ...[
                                SizedBox(height: gap),
                                _suspendUnsuspendButtons(),
                              ],
                            ],
                          ),
                        ),
                      ),
                      if (subscriptionDetails != null) ...[
                        Card(
                          margin: EdgeInsets.only(bottom: cardGap),
                          elevation: 4,
                          shadowColor: Colors.grey.shade300,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: const BorderSide(
                                  color: Colors.black87, width: 1.5)),
                          child: Padding(
                            padding: EdgeInsets.all(pad),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // ── تفاصيل الاشتراك ──
                                Text('تفاصيل الاشتراك',
                                    style: _TextStyles.sectionHeader
                                        .copyWith(fontSize: titleSize)),
                                if (_allSubscriptions.length > 1) ...[
                                  SizedBox(height: gap),
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      children: List.generate(
                                        _allSubscriptions.length,
                                        (i) {
                                          final sub = _allSubscriptions[i];
                                          final devDetails =
                                              _safeGetMap(sub['deviceDetails']);
                                          final devUsername = _safeGetString(
                                                  devDetails?['username']) ??
                                              '';
                                          final subStatus = sub['status']
                                                  is String
                                              ? sub['status'] as String
                                              : _safeGetString(
                                                      (sub['status'] as Map?)?[
                                                          'displayValue']) ??
                                                  '';
                                          final isActive =
                                              subStatus.toLowerCase() ==
                                                  'active';
                                          final isSelected =
                                              _selectedSubscriptionIndex == i;
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
                                          final pillLabel =
                                              devUsername.isNotEmpty
                                                  ? devUsername
                                                  : 'اشتراك ${i + 1}';
                                          return GestureDetector(
                                            onTap: () {
                                              setState(() {
                                                _selectedSubscriptionIndex = i;
                                                subscriptionDetails =
                                                    _allSubscriptions[i];
                                                deviceOntInfo = null;
                                                ontErrorMessage = '';
                                              });
                                              fetchDeviceOntInfo();
                                              final id = _extractSubscriptionId(
                                                  _allSubscriptions[i]);
                                              if (id != null && id.isNotEmpty)
                                                fetchFullSubscriptionDetails(
                                                    id);
                                            },
                                            child: Container(
                                              margin:
                                                  const EdgeInsetsDirectional
                                                      .only(end: 8),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 14,
                                                      vertical: 7),
                                              decoration: BoxDecoration(
                                                color: pillColor,
                                                borderRadius:
                                                    BorderRadius.circular(20),
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
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: textColor,
                                                    ),
                                                  ),
                                                  Text(
                                                    isActive
                                                        ? 'فعّال'
                                                        : 'منتهي',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      color: isSelected
                                                          ? Colors.white70
                                                          : isActive
                                                              ? Colors
                                                                  .green[700]!
                                                              : Colors
                                                                  .red[400]!,
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

                                // ── معلومات الجهاز + حالة الجهاز + قوة الإشارة ──
                                Divider(
                                    height: gap * 3,
                                    thickness: 1.5,
                                    color: Colors.black54),
                                Text('معلومات الجهاز',
                                    style: _TextStyles.sectionHeader
                                        .copyWith(fontSize: titleSize)),
                                SizedBox(height: gap),
                                _deviceAndOntCombined(deviceDetails),
                                SizedBox(height: gap),

                                // ── تحكم بالراوتر عن بعد (GenieACS) ──
                                _genieAcsButton(),
                                SizedBox(height: gap),

                                // ── الجلسة ──
                                if (activeSession != null) ...[
                                  Divider(
                                      height: gap * 3,
                                      thickness: 1.5,
                                      color: Colors.black54),
                                  Row(children: [
                                    Expanded(
                                        child: _sessionBox(activeSession!)),
                                  ]),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ] else ...[
                        Card(
                          elevation: 4,
                          shadowColor: Colors.grey.shade200,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                  color: Colors.grey.shade300, width: 1.5)),
                          child: const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('لا توجد تفاصيل اشتراك متاحة',
                                style: TextStyle(color: Colors.grey)),
                          ),
                        ),
                      ]
                    ],
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
                        fontWeight: FontWeight.w800)),
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
            initialCustomerPhone: _resolvedPhone.isNotEmpty
                ? _fmtPhoneLocal(_resolvedPhone)
                : _fmtPhoneLocal(widget.userPhone),
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
    try {
      final r = await AuthService.instance.authenticatedRequest('PUT',
          'https://admin.ftth.iq/api/subscriptions/${widget.subscriptionId}/device',
          body: jsonEncode(body));
      if (!mounted) return;
      if (r.statusCode == 200) {
        setState(() => errorMessage = 'تم التحديث بنجاح');
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) Navigator.of(context).pop(true);
        });
      } else if (r.statusCode == 401) {
        if (mounted) AuthErrorHandler.handle401Error(context);
        return;
      } else {
        setState(() => errorMessage = 'فشل: ${r.statusCode} - ${r.body}');
      }
    } catch (e) {
      if (mounted) setState(() => errorMessage = 'خطأ');
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

// ═══════ شاشة الجلسات والاستهلاك ═══════
class _SessionsUsageDialog extends StatefulWidget {
  final String subscriptionId;
  const _SessionsUsageDialog({required this.subscriptionId});

  @override
  State<_SessionsUsageDialog> createState() => _SessionsUsageDialogState();
}

class _SessionsUsageDialogState extends State<_SessionsUsageDialog> {
  bool _loadingUsage = true;
  bool _loadingSessions = true;
  Map<String, dynamic>? _totalUsage;
  List<Map<String, dynamic>> _sessions = [];
  int _totalSessions = 0;
  String? _usageError;
  String? _sessionsError;

  @override
  void initState() {
    super.initState();
    _fetchTotalUsage();
    _fetchSessionHistory();
  }

  Future<void> _fetchTotalUsage() async {
    try {
      final r = await AuthService.instance.authenticatedRequest('GET',
          'https://admin.ftth.iq/api/subscriptions/${widget.subscriptionId}/sessions/total-usage');
      if (!mounted) return;
      debugPrint(
          '[total-usage] status=${r.statusCode} body=${r.body.length > 800 ? r.body.substring(0, 800) : r.body}');
      if (r.statusCode == 200) {
        final parsed = jsonDecode(r.body);
        // دعم model{} wrapper
        final usage = parsed is Map &&
                parsed.containsKey('model') &&
                parsed['model'] is Map
            ? Map<String, dynamic>.from(parsed['model'])
            : (parsed is Map
                ? Map<String, dynamic>.from(parsed)
                : <String, dynamic>{});
        debugPrint('[total-usage] resolved keys=${usage.keys.toList()}');
        setState(() {
          _totalUsage = usage;
          _loadingUsage = false;
        });
      } else {
        setState(() {
          _usageError = 'خطأ: ${r.statusCode}';
          _loadingUsage = false;
        });
      }
    } catch (e) {
      debugPrint('[total-usage] error=$e');
      if (mounted)
        setState(() {
          _usageError = 'خطأ';
          _loadingUsage = false;
        });
    }
  }

  Future<void> _fetchSessionHistory() async {
    try {
      final r = await AuthService.instance.authenticatedRequest('GET',
          'https://admin.ftth.iq/api/subscriptions/${widget.subscriptionId}/sessions/history?pageSize=20&pageNumber=1');
      if (!mounted) return;
      debugPrint(
          '[sessions-history] status=${r.statusCode} body=${r.body.length > 800 ? r.body.substring(0, 800) : r.body}');
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body);
        final items = data['items'] as List? ?? [];
        if (items.isNotEmpty) {
          debugPrint(
              '[sessions-history] first item keys=${(items.first as Map).keys.toList()}');
          debugPrint('[sessions-history] first item=${items.first}');
        }
        setState(() {
          _sessions = items.map((e) => Map<String, dynamic>.from(e)).toList();
          _totalSessions = data['totalCount'] ?? items.length;
          _loadingSessions = false;
        });
      } else {
        setState(() {
          _sessionsError = 'خطأ: ${r.statusCode}';
          _loadingSessions = false;
        });
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _sessionsError = 'خطأ';
          _loadingSessions = false;
        });
    }
  }

  String _formatBytes(dynamic bytes) {
    if (bytes == null) return '0';
    final b = bytes is num
        ? bytes.toDouble()
        : double.tryParse(bytes.toString()) ?? 0;
    if (b >= 1073741824) return '${(b / 1073741824).toStringAsFixed(2)} GB';
    if (b >= 1048576) return '${(b / 1048576).toStringAsFixed(1)} MB';
    if (b >= 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '${b.toStringAsFixed(0)} B';
  }

  String _formatDate(dynamic date) {
    if (date == null) return '-';
    try {
      final dt = DateTime.parse(date.toString()).toLocal();
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return date.toString();
    }
  }

  String _formatDuration(dynamic seconds) {
    if (seconds == null) return '-';
    final s = seconds is num
        ? seconds.toInt()
        : int.tryParse(seconds.toString()) ?? 0;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    if (h > 0) return '$h ساعة $m دقيقة';
    return '$m دقيقة';
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final dialogWidth = (width * 0.85).clamp(400.0, 800.0);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: dialogWidth,
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.indigo.shade600,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.data_usage, color: Colors.white, size: 24),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('الجلسات وإجمالي الاستهلاك',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // إجمالي الاستهلاك
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: Colors.indigo.shade50,
              child: _loadingUsage
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : _usageError != null
                      ? Text(_usageError!,
                          style: const TextStyle(color: Colors.red))
                      : _buildUsageSection(),
            ),

            // عدد الجلسات
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.history, size: 18, color: Colors.grey),
                  const SizedBox(width: 6),
                  Text('سجل الجلسات ($_totalSessions جلسة)',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                ],
              ),
            ),

            // جدول الجلسات
            Expanded(
              child: _loadingSessions
                  ? const Center(child: CircularProgressIndicator())
                  : _sessionsError != null
                      ? Center(
                          child: Text(_sessionsError!,
                              style: const TextStyle(color: Colors.red)))
                      : _sessions.isEmpty
                          ? const Center(child: Text('لا توجد جلسات'))
                          : ListView.separated(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              itemCount: _sessions.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (ctx, i) =>
                                  _buildSessionItem(_sessions[i]),
                            ),
            ),

            // زر إغلاق
            Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('إغلاق',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _usageStat(IconData icon, String label, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 4),
        Text(label,
            style: TextStyle(
                fontSize: 12, color: color, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                fontSize: 16, color: color, fontWeight: FontWeight.w900)),
      ],
    );
  }

  // بناء قسم الاستهلاك — يعرض كل الحقول المتوفرة ديناميكياً
  Widget _buildUsageSection() {
    if (_totalUsage == null || _totalUsage!.isEmpty) {
      return const Text('لا توجد بيانات استهلاك',
          style: TextStyle(color: Colors.grey));
    }
    // محاولة عرض بحسب أسماء الحقول المعروفة
    final u = _totalUsage!;
    final dl = u['totalDownloadedBytes'] ??
        u['download'] ??
        u['totalDownload'] ??
        u['acctInputOctets'] ??
        u['inputOctets'];
    final ul = u['totalUploadedBytes'] ??
        u['upload'] ??
        u['totalUpload'] ??
        u['acctOutputOctets'] ??
        u['outputOctets'];

    if (dl != null || ul != null) {
      num dlNum = dl is num ? dl : (num.tryParse(dl?.toString() ?? '') ?? 0);
      num ulNum = ul is num ? ul : (num.tryParse(ul?.toString() ?? '') ?? 0);
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _usageStat(
              Icons.cloud_download, 'تحميل', _formatBytes(dlNum), Colors.blue),
          _usageStat(
              Icons.cloud_upload, 'رفع', _formatBytes(ulNum), Colors.orange),
          _usageStat(Icons.storage, 'الإجمالي', _formatBytes(dlNum + ulNum),
              Colors.indigo),
        ],
      );
    }

    // لم نجد الحقول المعروفة — نعرض كل الحقول الخام
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: u.entries.map((e) {
        final v = e.value;
        final display = v is Map ? v.toString() : (v?.toString() ?? 'null');
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Text('${e.key}: ',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      fontFamily: 'monospace')),
              Expanded(
                  child: SelectableText(display,
                      style: const TextStyle(
                          fontSize: 12, fontFamily: 'monospace'))),
            ],
          ),
        );
      }).toList(),
    );
  }

  // بناء عنصر جلسة واحد — يعرض الحقول ديناميكياً
  Widget _buildSessionItem(Map<String, dynamic> s) {
    // بحث عن الحقول بأسماء متعددة
    final startTime = s['startTime'] ??
        s['start'] ??
        s['sessionStart'] ??
        s['acctStartTime'] ??
        s['startDate'];
    final endTime = s['endTime'] ??
        s['end'] ??
        s['sessionEnd'] ??
        s['acctStopTime'] ??
        s['endDate'];
    final duration = s['duration'] ??
        s['sessionDuration'] ??
        s['sessionTimeInSeconds'] ??
        s['acctSessionTime'];
    final download = s['download'] ??
        s['downloadBytes'] ??
        s['bytesDown'] ??
        s['acctInputOctets'] ??
        s['inputOctets'];
    final upload = s['upload'] ??
        s['uploadBytes'] ??
        s['bytesUp'] ??
        s['acctOutputOctets'] ??
        s['outputOctets'];
    final sessionIp = s['ipAddress'] ??
        s['ip'] ??
        s['framedIpAddress'] ??
        s['framedIPAddress'];

    final hasKnownFields =
        startTime != null || duration != null || download != null;

    if (!hasKnownFields) {
      // عرض كل الحقول كـ raw data
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: s.entries.map((e) {
            final v = e.value;
            String display;
            if (v is Map) {
              display = (v['displayValue'] ?? v.toString()).toString();
            } else {
              display = v?.toString() ?? 'null';
            }
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Text('${e.key}: $display',
                  style:
                      const TextStyle(fontSize: 11, fontFamily: 'monospace')),
            );
          }).toList(),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.circle,
                  size: 8, color: endTime == null ? Colors.green : Colors.grey),
              const SizedBox(width: 6),
              Text(_formatDate(startTime),
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600)),
              if (endTime != null) ...[
                const Text(' → ',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                Text(_formatDate(endTime),
                    style: const TextStyle(fontSize: 12)),
              ] else
                const Text('  (نشط الآن)',
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.green,
                        fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              if (duration != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.timer, size: 14, color: Colors.blueGrey),
                    const SizedBox(width: 3),
                    Text(_formatDuration(duration),
                        style: const TextStyle(
                            fontSize: 11, color: Colors.blueGrey)),
                  ],
                ),
              if (download != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_downward,
                        size: 14, color: Colors.blue.shade600),
                    const SizedBox(width: 2),
                    Text(_formatBytes(download),
                        style: TextStyle(
                            fontSize: 11, color: Colors.blue.shade700)),
                  ],
                ),
              if (upload != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_upward,
                        size: 14, color: Colors.orange.shade600),
                    const SizedBox(width: 2),
                    Text(_formatBytes(upload),
                        style: TextStyle(
                            fontSize: 11, color: Colors.orange.shade700)),
                  ],
                ),
              if (sessionIp != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.language, size: 14, color: Colors.grey),
                    const SizedBox(width: 2),
                    Text(sessionIp.toString(),
                        style:
                            const TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════ واجهة إدارة الراوتر عن بعد (GenieACS) ═══════
class _RouterManagementDialog extends StatefulWidget {
  final String pppoeUsername;
  final String? serial;
  final String? mac;
  const _RouterManagementDialog({required this.pppoeUsername, this.serial, this.mac});

  @override
  State<_RouterManagementDialog> createState() => _RouterManagementDialogState();
}

class _RouterManagementDialogState extends State<_RouterManagementDialog> {
  bool _loading = true;
  String? _error;
  List<DeviceInfo> _devices = [];
  List<Map<String, dynamic>> _rawDevices = [];
  int _selectedDeviceIndex = 0;
  bool _actionLoading = false;
  String _actionMessage = '';

  DeviceInfo? get _device => _devices.isNotEmpty ? _devices[_selectedDeviceIndex] : null;

  @override
  void initState() {
    super.initState();
    _findDevices();
  }

  Future<void> _findDevices() async {
    setState(() { _loading = true; _error = null; });
    try {
      final rawList = await GenieAcsService.instance.findAllDevices(
          pppoeUsername: widget.pppoeUsername, serial: widget.serial, mac: widget.mac);
      if (!mounted) return;
      if (rawList.isNotEmpty) {
        setState(() {
          _rawDevices = rawList;
          _devices = rawList.map((r) => GenieAcsService.parseDevice(r)).toList();
          _selectedDeviceIndex = 0;
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'الجهاز غير متصل بنظام إدارة الراوترات (GenieACS)\nتأكد من ضبط إعدادات TR-069 في الراوتر';
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = 'خطأ في الاتصال: $e'; _loading = false; });
    }
  }

  Future<void> _doAction(String name, Future<bool> Function() action) async {
    setState(() { _actionLoading = true; _actionMessage = ''; });
    final ok = await action();
    if (!mounted) return;
    setState(() {
      _actionLoading = false;
      _actionMessage = ok ? 'تم تنفيذ "$name" بنجاح' : 'فشل تنفيذ "$name"';
    });
    if (ok) {
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) _findDevices(); // تحديث البيانات
      });
    }
  }

  void _showSetWifiDialog() {
    final ssidCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.wifi, color: Colors.teal),
            SizedBox(width: 8),
            Text('تغيير إعدادات WiFi', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ssidCtrl,
              decoration: const InputDecoration(
                labelText: 'اسم الشبكة (SSID)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.wifi),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passCtrl,
              decoration: const InputDecoration(
                labelText: 'كلمة المرور',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              final id = _device!.id;
              if (ssidCtrl.text.trim().isNotEmpty) {
                _doAction('تغيير SSID', () => GenieAcsService.instance.setWifiSsid(id, ssidCtrl.text.trim()));
              }
              if (passCtrl.text.trim().isNotEmpty) {
                _doAction('تغيير باسورد WiFi', () => GenieAcsService.instance.setWifiPassword(id, passCtrl.text.trim()));
              }
            },
            child: const Text('تطبيق', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final dialogWidth = (width * 0.85).clamp(400.0, 750.0);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.teal.shade700,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.settings_remote, color: Colors.white, size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('تحكم بالراوتر عن بعد',
                            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                        Text('PPPoE: ${widget.pppoeUsername}',
                            style: TextStyle(color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.white),
                    onPressed: _loading ? null : _findDevices,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            if (_loading)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('جاري البحث عن الجهاز...'),
                  ],
                ),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(Icons.router, size: 48, color: Colors.grey.shade400),
                    const SizedBox(height: 12),
                    Text(_error!, textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.red.shade700, fontSize: 14)),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text('إعادة المحاولة'),
                      onPressed: _findDevices,
                    ),
                  ],
                ),
              )
            else if (_device != null) ...[
              // تبديل بين الأجهزة (إذا أكثر من واحد)
              if (_devices.length > 1)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: Colors.teal.shade50,
                  child: Row(
                    children: [
                      Icon(Icons.device_hub, size: 16, color: Colors.teal.shade700),
                      const SizedBox(width: 8),
                      Text('${_devices.length} أجهزة مُدارة:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.teal.shade800)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: List.generate(_devices.length, (i) {
                              final d = _devices[i];
                              final selected = i == _selectedDeviceIndex;
                              return Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: ChoiceChip(
                                  label: Text(
                                    d.productClass.isNotEmpty ? d.productClass : (d.manufacturer.isNotEmpty ? d.manufacturer : 'جهاز ${i + 1}'),
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                                        color: selected ? Colors.white : Colors.teal.shade800),
                                  ),
                                  avatar: Icon(
                                    d.productClass.toLowerCase().contains('hg8') ? Icons.cell_tower : Icons.router,
                                    size: 14, color: selected ? Colors.white : Colors.teal.shade700,
                                  ),
                                  selected: selected,
                                  selectedColor: Colors.teal.shade700,
                                  backgroundColor: Colors.white,
                                  onSelected: (_) => setState(() { _selectedDeviceIndex = i; _actionMessage = ''; }),
                                ),
                              );
                            }),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // معلومات الجهاز المحدد
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // حالة الاتصال
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: _device!.isOnline ? Colors.green.shade50 : Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _device!.isOnline ? Colors.green.shade300 : Colors.red.shade300),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _device!.isOnline ? Icons.circle : Icons.circle_outlined,
                              size: 14,
                              color: _device!.isOnline ? Colors.green : Colors.red,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _device!.isOnline ? 'متصل' : 'غير متصل',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: _device!.isOnline ? Colors.green.shade800 : Colors.red.shade800,
                              ),
                            ),
                            const Spacer(),
                            Text('آخر اتصال: ${_device!.lastInformFormatted}',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // تفاصيل الجهاز
                      _infoGrid([
                        _infoItem(Icons.factory, 'الشركة', _device!.manufacturer),
                        _infoItem(Icons.router, 'الموديل', _device!.productClass),
                        _infoItem(Icons.memory, 'السيريال', _device!.serialNumber),
                        _infoItem(Icons.code, 'الفيرموير', _device!.softwareVersion),
                        _infoItem(Icons.language, 'WAN IP', _device!.wanIp),
                        _infoItem(Icons.hardware, 'الهاردوير', _device!.hardwareVersion),
                        if (_device!.lanIp.isNotEmpty)
                          _infoItem(Icons.home, 'LAN IP', _device!.lanIp),
                      ]),

                      // ═══ إعدادات WiFi ═══
                      if (_device!.wifiConfigs.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        _sectionHeader(Icons.wifi, 'شبكات WiFi (${_device!.wifiConfigs.length})'),
                        const SizedBox(height: 6),
                        ...(_device!.wifiConfigs.map((w) => _buildWifiCard(w))),
                      ],

                      // ═══ DHCP ═══
                      if (_device!.dhcpMinAddress.isNotEmpty || _device!.dhcpMaxAddress.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        _sectionHeader(Icons.dns, 'إعدادات DHCP'),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Column(
                            children: [
                              _dhcpRow('DHCP', _device!.dhcpEnabled ? 'مفعّل' : 'معطّل', _device!.dhcpEnabled ? Colors.green : Colors.red),
                              if (_device!.dhcpMinAddress.isNotEmpty)
                                _dhcpRow('النطاق', '${_device!.dhcpMinAddress} — ${_device!.dhcpMaxAddress}', Colors.blue.shade800),
                              if (_device!.dhcpSubnetMask.isNotEmpty)
                                _dhcpRow('Subnet', _device!.dhcpSubnetMask, Colors.grey.shade700),
                              if (_device!.dnsServers.isNotEmpty)
                                _dhcpRow('DNS', _device!.dnsServers, Colors.grey.shade700),
                            ],
                          ),
                        ),
                      ],

                      // ═══ الأجهزة المتصلة ═══
                      if (_device!.connectedHosts.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        _sectionHeader(Icons.devices, 'الأجهزة المتصلة (${_device!.connectedHosts.length})'),
                        const SizedBox(height: 6),
                        ...(_device!.connectedHosts.map((h) => Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.devices, size: 16, color: Colors.blueGrey),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(h.hostname.isNotEmpty ? h.hostname : 'جهاز غير معروف',
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                              ),
                              Text(h.ip, style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
                              const SizedBox(width: 8),
                              Text(h.mac, style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontFamily: 'monospace')),
                            ],
                          ),
                        ))),
                      ],

                      // رسالة حالة
                      if (_actionMessage.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(_actionMessage,
                              style: TextStyle(
                                color: _actionMessage.contains('بنجاح') ? Colors.green.shade700 : Colors.red.shade700,
                                fontWeight: FontWeight.w700,
                              )),
                        ),

                      const SizedBox(height: 16),

                      // أزرار التحكم
                      if (_actionLoading)
                        const CircularProgressIndicator()
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            _actionBtn(Icons.restart_alt, 'إعادة تشغيل', Colors.orange, () {
                              _confirmAction('إعادة تشغيل الراوتر', 'هل أنت متأكد؟ سيفقد المشترك الاتصال مؤقتاً.', () {
                                _doAction('إعادة تشغيل', () => GenieAcsService.instance.rebootDevice(_device!.id));
                              });
                            }),
                            _actionBtn(Icons.wifi, 'تغيير WiFi', Colors.teal, _showSetWifiDialog),
                            _actionBtn(Icons.speed, 'تحديد السرعة', Colors.deepPurple, _showBandwidthDialog),
                            _actionBtn(Icons.network_ping, 'تشخيص', Colors.indigo, _showDiagnosticsDialog),
                            _actionBtn(Icons.dns, 'تغيير DHCP', Colors.blue.shade700, _showDhcpDialog),
                            _actionBtn(Icons.refresh, 'تحديث البيانات', Colors.blue, () {
                              _doAction('تحديث', () => GenieAcsService.instance.refreshDevice(_device!.id));
                            }),
                            _actionBtn(Icons.restore, 'إعادة ضبط المصنع', Colors.red, () {
                              _confirmAction('إعادة ضبط المصنع', 'تحذير! سيتم مسح كل إعدادات الراوتر.\nهل أنت متأكد تماماً؟', () {
                                _doAction('ضبط المصنع', () => GenieAcsService.instance.factoryReset(_device!.id));
                              });
                            }),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ═══ Helper widgets for router management ═══
  Widget _sectionHeader(IconData icon, String title) {
    return Align(
      alignment: Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.teal.shade700),
          const SizedBox(width: 6),
          Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Colors.teal.shade800)),
        ],
      ),
    );
  }

  Widget _dhcpRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 70, child: Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600))),
          Text(value, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }

  Widget _buildWifiCard(WifiConfig w) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: w.is5Ghz ? Colors.purple.shade50 : Colors.teal.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: w.is5Ghz ? Colors.purple.shade200 : Colors.teal.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.wifi, size: 16, color: w.is5Ghz ? Colors.purple.shade700 : Colors.teal.shade700),
              const SizedBox(width: 6),
              Text(w.bandLabel, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
                  color: w.is5Ghz ? Colors.purple.shade700 : Colors.teal.shade700)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(w.ssid.isNotEmpty ? w.ssid : '(بدون اسم)',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              ),
              if (!w.enabled)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.red.shade700, borderRadius: BorderRadius.circular(8)),
                  child: const Text('معطّل', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
                ),
              if (w.hidden)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(Icons.visibility_off, size: 14, color: Colors.grey.shade600),
                ),
              // زر تعديل
              InkWell(
                onTap: () => _showEditWifiDialog(w),
                child: Icon(Icons.edit, size: 16, color: w.is5Ghz ? Colors.purple.shade600 : Colors.teal.shade600),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 12,
            children: [
              if (w.password.isNotEmpty)
                Text('كلمة المرور: ${w.password}', style: TextStyle(fontSize: 10, color: Colors.grey.shade700)),
              Text('القناة: ${w.autoChannel ? "تلقائي" : w.channel}', style: TextStyle(fontSize: 10, color: Colors.grey.shade700)),
              if (w.macFilterEnabled)
                Text('MAC Filter: مفعّل', style: TextStyle(fontSize: 10, color: Colors.orange.shade700, fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }

  void _showEditWifiDialog(WifiConfig w) {
    final ssidCtrl = TextEditingController(text: w.ssid);
    final passCtrl = TextEditingController(text: w.password);
    bool hidden = w.hidden;
    bool enabled = w.enabled;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Row(children: [
            Icon(Icons.wifi, color: w.is5Ghz ? Colors.purple : Colors.teal),
            const SizedBox(width: 8),
            Text('تعديل WiFi ${w.bandLabel}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: ssidCtrl, decoration: const InputDecoration(labelText: 'اسم الشبكة (SSID)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.wifi))),
              const SizedBox(height: 10),
              TextField(controller: passCtrl, decoration: const InputDecoration(labelText: 'كلمة المرور', border: OutlineInputBorder(), prefixIcon: Icon(Icons.lock))),
              const SizedBox(height: 8),
              SwitchListTile(title: const Text('إخفاء الشبكة', style: TextStyle(fontSize: 13)), value: hidden, dense: true,
                  onChanged: (v) => setLocal(() => hidden = v)),
              SwitchListTile(title: const Text('تفعيل الشبكة', style: TextStyle(fontSize: 13)), value: enabled, dense: true,
                  onChanged: (v) => setLocal(() => enabled = v)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
              onPressed: () {
                Navigator.pop(ctx);
                final id = _device!.id;
                final prefix = 'InternetGatewayDevice.LANDevice.1.WLANConfiguration.${w.index}';
                final params = <List<dynamic>>[];
                if (ssidCtrl.text.trim() != w.ssid) params.add(['\$prefix.SSID', ssidCtrl.text.trim(), 'xsd:string']);
                if (passCtrl.text.trim().isNotEmpty && passCtrl.text.trim() != w.password) params.add(['$prefix.KeyPassphrase', passCtrl.text.trim(), 'xsd:string']);
                if (hidden != w.hidden) params.add(['$prefix.SSIDAdvertisementEnabled', !hidden, 'xsd:boolean']);
                if (enabled != w.enabled) params.add(['$prefix.Enable', enabled, 'xsd:boolean']);
                if (params.isNotEmpty) {
                  _doAction('تعديل WiFi ${w.bandLabel}', () => GenieAcsService.instance.setParameters(id, params));
                }
              },
              child: const Text('تطبيق', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }

  // ═══ تحديد سرعة المشترك ═══
  void _showBandwidthDialog() {
    final downloadCtrl = TextEditingController();
    final uploadCtrl = TextEditingController();
    // باقات شائعة
    final presets = <Map<String, dynamic>>[
      {'label': '10 Mbps', 'down': 10240, 'up': 5120},
      {'label': '25 Mbps', 'down': 25600, 'up': 10240},
      {'label': '50 Mbps', 'down': 51200, 'up': 20480},
      {'label': '75 Mbps', 'down': 76800, 'up': 25600},
      {'label': '100 Mbps', 'down': 102400, 'up': 51200},
      {'label': 'بدون حد', 'down': 0, 'up': 0},
    ];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(children: [
          Icon(Icons.speed, color: Colors.deepPurple),
          SizedBox(width: 8),
          Text('تحديد سرعة المشترك', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // باقات جاهزة
            Wrap(
              spacing: 6, runSpacing: 6,
              children: presets.map((p) => ActionChip(
                label: Text(p['label'], style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                backgroundColor: Colors.deepPurple.shade50,
                onPressed: () {
                  downloadCtrl.text = p['down'].toString();
                  uploadCtrl.text = p['up'].toString();
                },
              )).toList(),
            ),
            const SizedBox(height: 14),
            TextField(controller: downloadCtrl, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'سرعة التحميل (Kbps)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.download), hintText: '51200 = 50Mbps')),
            const SizedBox(height: 10),
            TextField(controller: uploadCtrl, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'سرعة الرفع (Kbps)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.upload), hintText: '20480 = 20Mbps')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              final down = int.tryParse(downloadCtrl.text.trim()) ?? 0;
              final up = int.tryParse(uploadCtrl.text.trim()) ?? 0;
              if (down > 0 && up > 0) {
                _doAction('تحديد السرعة ${down ~/ 1024}Mbps/${up ~/ 1024}Mbps', () =>
                    GenieAcsService.instance.setBandwidthLimit(_device!.id, down, up));
              } else if (down == 0 && up == 0) {
                _doAction('إزالة حد السرعة', () =>
                    GenieAcsService.instance.setBandwidthLimit(_device!.id, 0, 0));
              }
            },
            child: const Text('تطبيق', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  // ═══ تشخيص (Ping / Traceroute) ═══
  void _showDiagnosticsDialog() {
    final hostCtrl = TextEditingController(text: '8.8.8.8');
    showDialog(
      context: context,
      builder: (_) => _DiagnosticsDialog(deviceId: _device!.id, hostCtrl: hostCtrl),
    );
  }

  void _showDhcpDialog() {
    final minCtrl = TextEditingController(text: _device!.dhcpMinAddress);
    final maxCtrl = TextEditingController(text: _device!.dhcpMaxAddress);
    final dnsCtrl = TextEditingController(text: _device!.dnsServers);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(children: [
          Icon(Icons.dns, color: Colors.blue),
          SizedBox(width: 8),
          Text('إعدادات DHCP', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: minCtrl, decoration: const InputDecoration(labelText: 'بداية النطاق (Min IP)', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: maxCtrl, decoration: const InputDecoration(labelText: 'نهاية النطاق (Max IP)', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: dnsCtrl, decoration: const InputDecoration(labelText: 'DNS Servers (مفصول بفاصلة)', border: OutlineInputBorder(), hintText: '8.8.8.8,1.1.1.1')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              final id = _device!.id;
              if (minCtrl.text.trim().isNotEmpty && maxCtrl.text.trim().isNotEmpty) {
                _doAction('تغيير نطاق DHCP', () => GenieAcsService.instance.setDhcpRange(id, minCtrl.text.trim(), maxCtrl.text.trim()));
              }
              if (dnsCtrl.text.trim().isNotEmpty && dnsCtrl.text.trim() != _device!.dnsServers) {
                _doAction('تغيير DNS', () => GenieAcsService.instance.setDnsServers(id, dnsCtrl.text.trim()));
              }
            },
            child: const Text('تطبيق', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  void _showTr069SetupDialog() {
    showDialog(
      context: context,
      builder: (_) => _Tr069SetupDialog(
        acsUrl: GenieAcsService.acsUrl,
        pppoeUsername: widget.pppoeUsername,
      ),
    );
  }

  void _confirmAction(String title, String message, VoidCallback onConfirm) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.orange),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        ]),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () { Navigator.pop(ctx); onConfirm(); },
            child: const Text('تأكيد', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Widget _actionBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return ElevatedButton.icon(
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: onTap,
    );
  }

  Widget _infoGrid(List<Widget> items) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items,
    );
  }

  Widget _infoItem(IconData icon, String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Container(
      width: 200,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.teal.shade700),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════ نافذة إعداد TR-069 على راوتر جديد ═══════
// ═══════ نافذة التشخيص (Ping / Traceroute) ═══════
class _DiagnosticsDialog extends StatefulWidget {
  final String deviceId;
  final TextEditingController hostCtrl;
  const _DiagnosticsDialog({required this.deviceId, required this.hostCtrl});
  @override
  State<_DiagnosticsDialog> createState() => _DiagnosticsDialogState();
}

class _DiagnosticsDialogState extends State<_DiagnosticsDialog> {
  bool _running = false;
  String _result = '';
  String _type = '';

  Future<void> _runPing() async {
    final host = widget.hostCtrl.text.trim();
    if (host.isEmpty) return;
    setState(() { _running = true; _result = 'جاري إرسال Ping إلى $host من الراوتر...'; _type = 'ping'; });
    final ok = await GenieAcsService.instance.startPing(widget.deviceId, host);
    if (!ok) { if (mounted) setState(() { _running = false; _result = 'فشل إرسال أمر Ping — الجهاز قد لا يدعم هذه الميزة'; }); return; }
    // انتظر النتائج
    setState(() => _result = 'تم الإرسال — جاري انتظار النتائج...');
    await Future.delayed(const Duration(seconds: 5));
    final ping = await GenieAcsService.instance.getPingResult(widget.deviceId);
    if (!mounted) return;
    if (ping != null) {
      setState(() { _running = false; _result = 'Ping $host:\n${ping.summary}'; });
    } else {
      setState(() { _running = false; _result = 'لم يتم استلام نتائج — حاول مرة أخرى'; });
    }
  }

  Future<void> _runTraceroute() async {
    final host = widget.hostCtrl.text.trim();
    if (host.isEmpty) return;
    setState(() { _running = true; _result = 'جاري Traceroute إلى $host من الراوتر...'; _type = 'trace'; });
    final ok = await GenieAcsService.instance.startTraceroute(widget.deviceId, host);
    if (!mounted) return;
    setState(() {
      _running = false;
      _result = ok
          ? 'تم إرسال أمر Traceroute بنجاح\nالنتائج ستظهر عند تحديث بيانات الجهاز'
          : 'فشل — الجهاز قد لا يدعم Traceroute';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: SizedBox(
          width: min(480, MediaQuery.of(context).size.width * 0.85),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade700,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.network_ping, color: Colors.white, size: 22),
                    const SizedBox(width: 8),
                    const Expanded(child: Text('تشخيص الشبكة من الراوتر', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16))),
                    IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: widget.hostCtrl,
                      decoration: const InputDecoration(
                        labelText: 'العنوان (IP أو Domain)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.language),
                        hintText: '8.8.8.8 أو google.com',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: _running && _type == 'ping'
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.network_ping, size: 18),
                            label: const Text('Ping', style: TextStyle(fontWeight: FontWeight.w800)),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
                            onPressed: _running ? null : _runPing,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: _running && _type == 'trace'
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.route, size: 18),
                            label: const Text('Traceroute', style: TextStyle(fontWeight: FontWeight.w800)),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
                            onPressed: _running ? null : _runTraceroute,
                          ),
                        ),
                      ],
                    ),
                    if (_result.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: SelectableText(_result,
                            style: const TextStyle(fontSize: 12, fontFamily: 'monospace', height: 1.5)),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tr069SetupDialog extends StatefulWidget {
  final String acsUrl;
  final String pppoeUsername;
  const _Tr069SetupDialog({required this.acsUrl, required this.pppoeUsername});

  @override
  State<_Tr069SetupDialog> createState() => _Tr069SetupDialogState();
}

class _Tr069SetupDialogState extends State<_Tr069SetupDialog> {
  bool _scanning = false;
  List<RouterDetectResult> _results = [];
  String? _scanError;

  Future<void> _scan() async {
    setState(() { _scanning = true; _scanError = null; _results = []; });
    try {
      final results = await GenieAcsService.scanLocalNetwork();
      if (!mounted) return;
      setState(() {
        _results = results;
        _scanning = false;
        if (results.isEmpty) _scanError = 'لم يتم العثور على أي راوتر على الشبكة المحلية';
      });
    } catch (e) {
      if (mounted) setState(() { _scanning = false; _scanError = 'خطأ: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final dialogWidth = (width * 0.85).clamp(420.0, 700.0);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.indigo.shade700,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.settings_input_antenna, color: Colors.white, size: 24),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('إعداد TR-069 على راوتر جديد',
                            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                        Text('ربط راوتر المشترك بنظام الإدارة',
                            style: TextStyle(color: Colors.white70, fontSize: 11)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // إعدادات ACS الجاهزة للنسخ
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.indigo.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.vpn_key, size: 16, color: Colors.indigo.shade700),
                            const SizedBox(width: 6),
                            Text('إعدادات TR-069 المطلوبة', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Colors.indigo.shade800)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _copyableField('ACS URL', widget.acsUrl),
                        const SizedBox(height: 6),
                        _copyableField('Periodic Inform', 'Enabled — كل 300 ثانية'),
                        const SizedBox(height: 6),
                        _copyableField('Username / Password', 'فارغ (اتركه فارغ)'),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // زر فحص الشبكة
                  ElevatedButton.icon(
                    icon: _scanning
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.radar, size: 20),
                    label: Text(_scanning ? 'جاري الفحص...' : 'فحص الشبكة — كشف الراوتر',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _scanning ? null : _scan,
                  ),

                  if (_scanError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(_scanError!, textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.red.shade700, fontSize: 12)),
                    ),

                  // نتائج الفحص
                  if (_results.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text('الراوترات المكتشفة:', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Colors.indigo.shade800)),
                    const SizedBox(height: 8),
                    ..._results.map((r) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: r.supportsTr069 ? Colors.green.shade50 : Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: r.supportsTr069 ? Colors.green.shade300 : Colors.orange.shade300),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.router, size: 20, color: r.supportsTr069 ? Colors.green.shade700 : Colors.orange.shade700),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('${r.brand}${r.pageTitle.isNotEmpty ? ' — ${r.pageTitle}' : ''}',
                                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13,
                                            color: r.supportsTr069 ? Colors.green.shade800 : Colors.orange.shade800)),
                                    Text(r.ip, style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: r.supportsTr069 ? Colors.green.shade700 : Colors.orange.shade700,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  r.supportsTr069 ? 'يدعم TR-069' : 'لا يدعم',
                                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('مسار الإعداد:', style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                Text(r.tr069Path.isNotEmpty ? r.tr069Path : 'غير محدد — ابحث في Advanced Settings',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                                        color: r.supportsTr069 ? Colors.indigo.shade800 : Colors.red.shade700)),
                              ],
                            ),
                          ),
                          if (r.supportsTr069) ...[
                            const SizedBox(height: 8),
                            Text(
                              '1. افتح http://${r.ip}\n2. ادخل ${r.tr069Path}\n3. الصق ACS URL أعلاه\n4. فعّل Periodic Inform (300 ثانية)',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade700, height: 1.5),
                            ),
                          ],
                        ],
                      ),
                    )),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _copyableField(String label, String value) {
    return Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.indigo.shade200),
            ),
            child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, fontFamily: 'monospace')),
          ),
        ),
        const SizedBox(width: 4),
        InkWell(
          onTap: () {
            Clipboard.setData(ClipboardData(text: value));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('تم نسخ $label'), duration: const Duration(seconds: 1)),
            );
          },
          child: Icon(Icons.copy, size: 16, color: Colors.indigo.shade400),
        ),
      ],
    );
  }
}
