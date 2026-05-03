/// اسم الصفحة: إدارة التذاكر والطلبات
/// وصف الصفحة: صفحة عرض وإدارة تذاكر الدعم الفني والطلبات
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/auth_service.dart';
import '../../services/badge_service.dart';
import 'tktat_details_page.dart';
import '../auth/auth_error_handler.dart';
import 'create_ticket_page.dart';
import '../../utils/status_translator.dart';
import '../../services/ticket_updates_service.dart';

// امتداد لمساعدة تدرج الألوان (تفتيح/تغميق)
extension ColorShadeX on Color {
  Color darken([double amount = .1]) {
    final hsl = HSLColor.fromColor(this);
    final adjusted =
        hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));
    return adjusted.toColor();
  }

  Color lighten([double amount = .1]) {
    final hsl = HSLColor.fromColor(this);
    final adjusted =
        hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0));
    return adjusted.toColor();
  }
}

class TKTATsPage extends StatefulWidget {
  final String authToken;
  final String initialTab; // 'all', 'open'
  const TKTATsPage({super.key, required this.authToken, this.initialTab = 'open'});

  @override
  State<TKTATsPage> createState() => _TKTATsPageState();
}

class _TKTATsPageState extends State<TKTATsPage> {
  List<dynamic> tktats = [];
  List<dynamic> filteredTKTATs = [];
  final ScrollController _listController =
      ScrollController(); // للتحكم في Scrollbar الدائم
  bool isLoading = true;
  String message = "";
  int totalTKTATs = 0;
  int currentPage = 1;
  late String selectedTicketType; // 'all', 'open'
  String filterCategory = 'zone';
  String filterText = "";
  Timer? refreshTimer;
  FlutterLocalNotificationsPlugin localNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  bool isFilterVisible = false;
  Set<String> seenTKTATIds = <String>{}; // لتتبع المهام المرئية سابقاً
  bool isFirstLoad = true; // لتجنب إشعار التحميل الأول
  String? lastErrorDetails; // تفاصيل آخر خطأ حدث
  String? lastRequestUrl; // آخر رابط تم طلبه
  Map<String, String>? lastRequestHeaders; // آخر headers تم إرسالها

  // متغيرات جديدة للإشعارات
  int newTicketsCount = 0; // عدد التذاكر الجديدة
  List<dynamic> notifications = []; // قائمة الإشعارات
  bool showNotificationBadge = false; // لإظهار دائرة الإشعار الحمراء
  // تم إزالة المؤشر المتحرك والوميض
  bool _uiUpdatesSuspended = false; // لتعليق التحديثات أثناء فتح التفاصيل
  bool _fetchInProgress = false; // منع تداخل طلبات الشبكة

  // إخفاء التذاكر محلياً
  Set<String> _hiddenTicketIds = {};
  bool _showHidden = false;
  bool _hideInProgress = true; // إخفاء "قيد المعالجة" افتراضياً

  @override
  void initState() {
    super.initState();
    selectedTicketType = widget.initialTab;
    // مسح الشارة عند فتح الصفحة (لا يحتاج تأجيل)
    BadgeService.instance.clear();
    _loadHiddenTickets();
    // ⚡ تأجيل التحميل حتى بعد انتهاء transition animation
    WidgetsBinding.instance.addPostFrameCallback((_) {
      fetchTKTATs();
      setupNotifications();
      startAutoRefresh();
    });
  }

  @override
  void dispose() {
    refreshTimer?.cancel();
    _listController.dispose();
    super.dispose();
  }

  void setupNotifications() {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    localNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // التعامل مع النقر على الإشعار
        if (response.payload != null) {
          // يمكن إضافة منطق للانتقال لصفحة معينة
          fetchTKTATs();
        }
      },
    );

    // طلب الأذونات للأندرويد 13+
    _requestNotificationPermissions();
  }

  Future<void> _requestNotificationPermissions() async {
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        localNotificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidImplementation != null) {
      final bool? granted =
          await androidImplementation.requestNotificationsPermission();
      if (granted != true) {
        debugPrint('Notification permission denied');
      }
    }
  }

  Future<void> showNotification(String title, String body,
      {String? payload, bool playSound = true}) async {
    final AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'tktats_channel',
      'TKTATs Updates',
      channelDescription: 'Notification channel for TKTAT updates',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
      icon: '@mipmap/ic_launcher',
      color: Color(0xFF2196F3), // لون الإشعار
      ticker: 'مهمة جديدة',
      styleInformation: BigTextStyleInformation(
        body,
        contentTitle: title,
        summaryText: 'تطبيق FTTH',
      ),
    );

    const DarwinNotificationDetails iOSPlatformChannelSpecifics =
        DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'default',
    );

    final NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: iOSPlatformChannelSpecifics,
    );

    await localNotificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      platformChannelSpecifics,
      payload: payload,
    );
  }

  // إظهار إشعار مرئي داخل التطبيق
  void showInAppNotification(String message, {Color? backgroundColor}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.notification_important, color: Colors.white),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: backgroundColor ?? Colors.blue[600],
          duration: Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: EdgeInsets.all(16),
          action: SnackBarAction(
            label: 'تحديث',
            textColor: Colors.white,
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              fetchTKTATs();
            },
          ),
        ),
      );
    }
  }

  // دالة مساعدة لإرسال إشعار شامل (نظام + داخل التطبيق)
  Future<void> showCompleteNotification(String title, String body,
      {String? payload}) async {
    debugPrint('🔔 showCompleteNotification called - Title: $title, Body: $body');

    try {
      // إشعار النظام
      await showNotification(title, body, payload: payload);
      debugPrint('✅ System notification sent successfully');

      // إشعار داخل التطبيق
      showInAppNotification('$title: $body',
          backgroundColor: Colors.green[600]);
      debugPrint('✅ In-app notification sent successfully');
    } catch (e) {
      debugPrint('❌ Error sending notifications');
    }
  }

  void startAutoRefresh() {
    // منع إنشاء أكثر من مؤقت
    refreshTimer?.cancel();
    refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (!mounted) return;
      // تأكد أننا لسنا في حالة تحميل أصلاً لتقليل الضغط
      if (!isLoading) {
        fetchTKTATs(showNotificationOnNewTKTATs: true);
      }
    });
  }

  void pauseAutoRefresh() {
    refreshTimer?.cancel();
    refreshTimer = null;
  }

  void resumeAutoRefresh() {
    if (refreshTimer == null) {
      startAutoRefresh();
    }
  }

  Future<void> fetchTKTATs({bool showNotificationOnNewTKTATs = false}) async {
    if (_fetchInProgress) {
      debugPrint(
          '[fetchTKTATs] تم تجاهل طلب جديد لأن هناك طلب قيد التنفيذ - time=${DateTime.now()}');
      return;
    }
    _fetchInProgress = true;
    final fetchStart = DateTime.now();
    debugPrint(
        '[fetchTKTATs] بدء الجلب suspended=$_uiUpdatesSuspended showNotify=$showNotificationOnNewTKTATs page=$currentPage at $fetchStart');
    if (!_uiUpdatesSuspended) {
      setState(() {
        isLoading = true;
        message = "";
      });
    } else {
      // إذا الواجهة معلقة لا نغير مؤشر التحميل حتى لا يظهر وميض عند الرجوع
      isLoading = true;
      message = "";
    }

    // التحقق من الاتصال بالإنترنت أولاً
    if (!await checkInternetConnection()) {
      return;
    }

    try {
      // التحقق من التوكن أولاً
      if (widget.authToken.isEmpty) {
        setState(() {
          message = "التوكن غير متوفر، يرجى تسجيل الدخول مرة أخرى";
          isLoading = false;
        });
        return;
      }
      // status=0 يجلب التذاكر المفتوحة فقط من السيرفر (أسرع بكثير)
      final statusFilter = selectedTicketType == 'open' ? '&status=0' : '';
      final pageSize = selectedTicketType == 'open' ? 50 : 50;
      final url = Uri.parse(
          'https://admin.ftth.iq/api/support/tickets?pageSize=$pageSize&pageNumber=$currentPage&sortCriteria.property=createdAt&sortCriteria.direction=desc$statusFilter&hierarchyLevel=0');

      // حفظ تفاصيل الطلب للمساعدة في التشخيص
      lastRequestUrl = url.toString();
      final currentToken = await AuthService.instance.getAccessToken() ?? '';
      lastRequestHeaders = {
        'Authorization': 'Bearer $currentToken',
        'Accept': 'application/json, text/plain, */*',
        'Content-Type': 'application/json',
        'X-Client-App': '53d57a7f-3f89-4e9d-873b-3d071bc6dd9f',
        'X-User-Role': '0',
        'Origin': 'https://admin.ftth.iq',
        'Referer': 'https://admin.ftth.iq/',
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36',
      };

      debugPrint('Fetching TKTATs from: $url');
      debugPrint('Using token: ${currentToken.length > 20 ? currentToken.substring(0, 20) : currentToken}...');

      final response = await AuthService.instance.authenticatedRequest(
        'GET',
        url.toString(),
        headers: {
          'Accept': 'application/json, text/plain, */*',
          'Content-Type': 'application/json',
          'X-Client-App': '53d57a7f-3f89-4e9d-873b-3d071bc6dd9f',
          'X-User-Role': '0',
          'Origin': 'https://admin.ftth.iq',
          'Referer': 'https://admin.ftth.iq/',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36',
        },
      );

      debugPrint('Response status: ${response.statusCode}');
      debugPrint(
          'Response body: ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}...');
      if (response.statusCode == 200) {
        debugPrint(
            '[fetchTKTATs] ✅ نجاح الجلب بعد ${DateTime.now().difference(fetchStart).inMilliseconds} ms');
        final data = json.decode(response.body);
        final newTKTATs =
            (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];

        // تحسين منطق اكتشاف المهام الجديدة
        if (!_uiUpdatesSuspended &&
            showNotificationOnNewTKTATs &&
            !isFirstLoad &&
            tktats.isNotEmpty) {
          debugPrint('🔔 بدء فحص المهام الجديدة...');
          debugPrint('عدد المهام السابقة: ${tktats.length}');
          debugPrint('عدد المهام الجديدة: ${newTKTATs.length}');

          // البحث عن مهام جديدة حقيقية
          final List<Map<String, dynamic>> reallyNewTasks = [];

          for (var newTask in newTKTATs) {
            final newId = newTask['id']?.toString() ?? '';
            if (newId.isEmpty) continue;

            // التحقق من أن هذه المهمة لم تُر من قبل
            if (!seenTKTATIds.contains(newId)) {
              // التحقق من أن هذه المهمة ليست في القائمة السابقة
              final isReallyNew =
                  !tktats.any((oldTask) => oldTask['id']?.toString() == newId);

              if (isReallyNew) {
                reallyNewTasks.add(newTask);
                seenTKTATIds.add(newId);
              }
            }
          }

          debugPrint('عدد المهام الجديدة الحقيقية: ${reallyNewTasks.length}');

          if (reallyNewTasks.isNotEmpty) {
            // إشعار النظام
            await showEnhancedNotification(
              reallyNewTasks.length,
              reallyNewTasks,
            );

            // إشعار داخل التطبيق مع تفاصيل أكثر
            await showEnhancedInAppNotification(
              reallyNewTasks.length,
              reallyNewTasks,
            );
          }
        }

        // تحديث البيانات دائماً داخلياً
        tktats = newTKTATs;
        totalTKTATs = data['totalCount'] ?? 0;

        // تنظيف المخفيات: إزالة IDs التذاكر المحلولة التي لم تعد في الـ API
        _cleanupHiddenTickets(newTKTATs);

        // مزامنة عدد التذاكر المفتوحة (غير المخفية) مع الفقاعة العائمة
        final openCount = newTKTATs.where((t) {
          final s = (t['status']?.toString() ?? '').trim().toLowerCase();
          final tId = t['self']?['id']?.toString() ?? t['id']?.toString() ?? '';
          final isInProgress = s.contains('in progress');
          final isOpen = s.contains('new') ||
              isInProgress ||
              s.contains('waiting') ||
              s.contains('on hold') ||
              s.contains('contractor') ||
              s.contains('reopened');
          if (_hideInProgress && isInProgress) return false;
          return isOpen && !_hiddenTicketIds.contains(tId);
        }).length;
        TicketUpdatesService.instance.updateAgentCount(openCount);
        if (!_uiUpdatesSuspended && mounted) {
          setState(() {
            filterTKTATs();
            isLoading = false;
            message = newTKTATs.isEmpty ? "لا توجد مهام متاحة" : "";
            isFirstLoad = false;
          });
        } else {
          // عند التعليق نجهز الفلاتر للرجوع بدون setState كثيف
          filterTKTATs();
          isFirstLoad = false;
          isLoading = false; // حفظ الحالة ليظهر جاهز عند الرجوع
        }
      } else if (response.statusCode == 401) {
        lastErrorDetails =
            'كود الخطأ: 401 - Unauthorized\nالرسالة: انتهت صلاحية جلسة المستخدم\nاستجابة الخادم: ${response.body}';
        if (!_uiUpdatesSuspended && mounted) {
          setState(() {
            message = "انتهت صلاحية جلسة المستخدم، يرجى تسجيل الدخول مرة أخرى";
            isLoading = false;
          });
        }
        AuthErrorHandler.handle401Error(context);
      } else if (response.statusCode == 403) {
        lastErrorDetails =
            'كود الخطأ: 403 - Forbidden\nالرسالة: ليس لديك صلاحية للوصول\nاستجابة الخ��دم: ${response.body}';
        if (!_uiUpdatesSuspended && mounted) {
          setState(() {
            message = "ليس لديك صلاحية للوصول إلى هذه البيانات";
            isLoading = false;
          });
        }
      } else if (response.statusCode == 404) {
        lastErrorDetails =
            'كود الخطأ: 404 - Not Found\nالرسالة: لم يتم العثور على البيانات\nاستجابة الخادم: ${response.body}';
        if (!_uiUpdatesSuspended && mounted) {
          setState(() {
            message = "لم يتم العثور على البيانات المطلوبة";
            isLoading = false;
          });
        }
      } else if (response.statusCode >= 500) {
        lastErrorDetails =
            'كود الخطأ: ${response.statusCode} - Server Error\nالرسالة: خطأ في الخادم\nاستجابة الخادم: ${response.body}';
        if (!_uiUpdatesSuspended && mounted) {
          setState(() {
            message =
                "خطأ في الخادم (${response.statusCode})، يرجى المحاولة لاحقاً";
            isLoading = false;
          });
        }
      } else {
        lastErrorDetails =
            'كود الخطأ: ${response.statusCode}\nالرسالة: فشل غير متوقع\nاستجابة الخادم: ${response.body}';
        if (!_uiUpdatesSuspended && mounted) {
          setState(() {
            message =
                "فشل جلب البيانات: كود الخطأ ${response.statusCode}\nانقر لعرض التفاصيل";
            isLoading = false;
          });
        }
      }
    } on TimeoutException {
      lastErrorDetails =
          'نوع الخطأ: TimeoutException\nالرسالة: انتهت مهلة الاتصال (30 ثانية)\nالسبب المحتمل: بطء في الاتصال أو عدم استجابة الخادم';
      if (!_uiUpdatesSuspended && mounted) {
        setState(() {
          message = "انتهت مهلة الاتصال، يرجى التحقق من الاتصال بالإنترنت";
          isLoading = false;
        });
      }
    } on http.ClientException catch (e) {
      lastErrorDetails =
          'نوع الخطأ: ClientException\nالرسالة: ${e.message}\nالسبب المحتمل: مشكلة في الشبكة أو إعدادات الاتصال';
      if (!_uiUpdatesSuspended && mounted) {
        setState(() {
          message = "خطأ في الشبكة: ${e.message}";
          isLoading = false;
        });
      }
    } catch (e) {
      lastErrorDetails =
          'نوع الخطأ: Exception\nالرسالة: $e\nالسبب: خطأ غير متوقع في التطبيق';
      if (!_uiUpdatesSuspended && mounted) {
        setState(() {
          message = "حدث خطأ غير متوقع: $e";
          isLoading = false;
        });
      }
      debugPrint('Error details');
    }
    debugPrint(
        '[fetchTKTATs] انتهاء الجلب success=${!isLoading} suspended=$_uiUpdatesSuspended مدة=${DateTime.now().difference(fetchStart).inMilliseconds} ms');
    _fetchInProgress = false;
  }

  // === إخفاء التذاكر محلياً ===
  Future<void> _loadHiddenTickets() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('hidden_ticket_ids') ?? [];
    setState(() => _hiddenTicketIds = list.toSet());
  }

  Future<void> _saveHiddenTickets() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('hidden_ticket_ids', _hiddenTicketIds.toList());
  }

  /// تنظيف المخفيات: إزالة IDs التذاكر التي لم تعد موجودة في بيانات الـ API
  void _cleanupHiddenTickets(List<dynamic> currentTktats) {
    if (_hiddenTicketIds.isEmpty) return;

    // جمع كل IDs التذاكر الحالية من الـ API
    final activeIds = <String>{};
    for (final t in currentTktats) {
      final id = t['self']?['id']?.toString() ?? t['id']?.toString() ?? '';
      if (id.isNotEmpty) activeIds.add(id);
    }

    // إزالة أي ID مخفي لم يعد موجوداً
    final removed = _hiddenTicketIds.difference(activeIds);
    if (removed.isNotEmpty) {
      debugPrint('🧹 تنظيف ${removed.length} تذكرة مخفية محلولة: $removed');
      _hiddenTicketIds.removeAll(removed);
      _saveHiddenTickets();
    }
  }

  void _toggleHideTicket(String ticketId) {
    setState(() {
      if (_hiddenTicketIds.contains(ticketId)) {
        _hiddenTicketIds.remove(ticketId);
      } else {
        _hiddenTicketIds.add(ticketId);
      }
    });
    _saveHiddenTickets();
    filterTKTATs();
    setState(() {});
  }

  void filterTKTATs() {
    filteredTKTATs = tktats.where((tktat) {
      final rawStatus = tktat['status']?.toString() ?? '';
      final status = canonicalStatusKey(rawStatus);
      final valueToFilter =
          tktat[filterCategory]?.toString().toLowerCase() ?? '';

      // فحص النص المدخل (إذا وجد)
      bool matchesFilterText = true;
      if (filterText.isNotEmpty) {
        matchesFilterText = valueToFilter.contains(filterText.toLowerCase());
      }

      // عرض التذاكر المفتوحة فقط (أو الكل إذا اختار المستخدم)
      final isOpen = (status == 'new' || status == 'in progress' || status == 'pending');
      bool matchesTicketType = true;
      if (selectedTicketType == 'open') {
        matchesTicketType = isOpen;
      }

      // إخفاء "قيد المعالجة" إذا مفعّل
      if (_hideInProgress && status == 'in progress') return false;

      // فلترة المخفية
      final ticketId = tktat['self']?['id']?.toString() ?? tktat['id']?.toString() ?? '';
      if (!_showHidden && _hiddenTicketIds.contains(ticketId)) return false;
      if (_showHidden && !_hiddenTicketIds.contains(ticketId)) return false;

      // يجب أن تتطابق مع كلا الشرطين
      return matchesFilterText && matchesTicketType;
    }).toList();
  }

  void onRefresh() {
    fetchTKTATs();
  }

  void resetFilters() {
    setState(() {
      filterText = "";
      selectedTicketType = 'open';
      currentPage = 1;
    });
    fetchTKTATs();
  }

  void nextPage() {
    setState(() {
      currentPage++;
    });
    fetchTKTATs();
  }

  void previousPage() {
    if (currentPage > 1) {
      setState(() {
        currentPage--;
      });
      fetchTKTATs();
    }
  }

  void navigateToTaskDetails(BuildContext context, dynamic task) {
    // إيقاف التحديثات الشبكية + تعليق تحديثات الواجهة
    pauseAutoRefresh();
    _uiUpdatesSuspended = true;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TKTATDetailsPage(
          tktat: task,
          authToken: widget.authToken,
        ),
      ),
    ).then((_) {
      // استئناف بعد الرجوع: تحديث واحد فوري ثم إعادة المؤقت
      if (mounted) {
        _uiUpdatesSuspended = false;
        // تحديث واحد لإظهار أي تغييرات حدثت أثناء التعليق
        fetchTKTATs();
        resumeAutoRefresh();
      }
    });
  }

  void toggleFilterVisibility() {
    setState(() {
      isFilterVisible = !isFilterVisible;
    });
  }

  // Helper function to get status color
  Color getStatusColor(String? status) => statusColor(status);

  // Helper function to get status icon
  IconData getStatusIcon(String? status) {
    final s = canonicalStatusKey(status);
    switch (s) {
      case 'in progress':
        return Icons.hourglass_empty;
      case 'completed':
        return Icons.check_circle;
      case 'pending':
        return Icons.pending;
      case 'cancelled':
        return Icons.cancel;
      case 'new':
        return Icons.fiber_new;
      case 'assigned':
        return Icons.assignment_ind;
      default:
        return Icons.help_outline;
    }
  }

  // Helper function to get priority color
  Color getPriorityColor(String? priority) {
    switch (priority?.toLowerCase()) {
      case 'high':
        return Colors.red;
      case 'medium':
        return Colors.orange;
      case 'low':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  // Helper function to translate status to Arabic
  String translateStatus(String status) => translateTicketStatus(status);

  // Helper function to translate priority to Arabic
  String translatePriority(String priority) {
    switch (priority.toLowerCase()) {
      case 'high':
        return 'عالية';
      case 'medium':
        return 'متوسطة';
      case 'low':
        return 'منخفضة';
      default:
        return priority;
    }
  }

  // Helper function to format date
  String formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr).toLocal();
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return dateStr;
    }
  }

  // عرض تفاصيل الخطأ في نافذة منبثقة قابلة للنسخ
  void showErrorDetailsDialog() {
    if (lastErrorDetails == null) {
      showInAppNotification('لا توجد تفاصيل خطأ متوفرة');
      return;
    }

    final DateTime now = DateTime.now();
    final String timestamp =
        '${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute}:${now.second}';

    final String fullErrorReport = '''
=== تقرير خطأ FTTH ===
الوقت: $timestamp
الصفحة: صفحة المهام
رقم الصفحة الحالية: $currentPage
التوكن: ${widget.authToken.isNotEmpty ? '${widget.authToken.substring(0, 20)}...' : 'غير متوفر'}

--- تفاصيل الطلب ---
الرابط: ${lastRequestUrl ?? 'غير متوفر'}
Headers: ${lastRequestHeaders?.toString() ?? 'غير متوفر'}

--- تفاصيل الخطأ ---
$lastErrorDetails

--- معلومات النظام ---
المنصة: Windows
التطبيق: FTTH Project
الإصدار: 1.0.0

--- إعدادات الفلترة ---
نوع التذاكر المحدد: $selectedTicketType
فئة الفلتر: $filterCategory
نص البحث: ${filterText.isEmpty ? 'فارغ' : filterText}
عدد المهام المعروضة: ${filteredTKTATs.length}
العدد الكلي: $totalTKTATs
''';

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.error_outline, color: Colors.red),
              SizedBox(width: 8),
              Text('تفاصيل الخطأ'),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: min(400, MediaQuery.of(context).size.height * 0.6),
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: SelectableText(
                        fullErrorReport,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: fullErrorReport));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('تم نسخ تفاصيل الخطأ إلى الحافظة'),
                            backgroundColor: Colors.green,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      icon: Icon(Icons.copy),
                      label: Text('نسخ'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[600],
                        foregroundColor: Colors.white,
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        fetchTKTATs(); // إعادة المحاولة
                      },
                      icon: Icon(Icons.refresh),
                      label: Text('إعادة المحاولة'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[600],
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('إغلاق'),
            ),
          ],
        );
      },
    );
  }

  // التحقق من الاتصال بالإنترنت
  Future<bool> checkInternetConnection() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult.contains(ConnectivityResult.none)) {
        setState(() {
          message = "لا يوجد اتصال بالإنترنت، يرجى التحقق من الاتصال";
          isLoading = false;
        });
        showInAppNotification(
          'لا يوجد اتصال بالإنترنت',
          backgroundColor: Colors.orange[600],
        );
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('Error checking connectivity');
      return true; // افتراض وجود اتصال في حالة الخطأ
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 4,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        toolbarHeight: 78, // رفع ارتفاع الشريط ليتناسق مع البطاقة
        shadowColor: Colors.blue.withValues(alpha: 0.3),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
        ),
        centerTitle: true,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.blue[700]!,
                Colors.blue[500]!,
                Colors.indigo[400]!,
              ],
            ),
          ),
        ),
        title: totalTKTATs > 0
            ? _buildCountCard()
            : Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.task_alt, color: Colors.white, size: 22),
              ),
        actions: [
          // زر إظهار/إخفاء "قيد المعالجة"
          Container(
            margin: EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: _hideInProgress ? Colors.white.withValues(alpha: 0.15) : Colors.blue.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: IconButton(
              icon: Icon(_hideInProgress ? Icons.hourglass_disabled : Icons.hourglass_top, size: 20),
              tooltip: _hideInProgress ? 'إظهار قيد المعالجة' : 'إخفاء قيد المعالجة',
              onPressed: () {
                setState(() => _hideInProgress = !_hideInProgress);
                filterTKTATs();
              },
              color: Colors.white,
              iconSize: 20,
            ),
          ),
          // زر إظهار/إخفاء المخفية
          if (_hiddenTicketIds.isNotEmpty)
            Container(
              margin: EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: _showHidden ? Colors.orange.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: IconButton(
                icon: Badge(
                  isLabelVisible: !_showHidden,
                  label: Text('${_hiddenTicketIds.length}', style: TextStyle(fontSize: 10)),
                  child: Icon(_showHidden ? Icons.visibility : Icons.visibility_off, size: 20),
                ),
                tooltip: _showHidden ? 'إظهار التذاكر النشطة' : 'إظهار المخفية (${_hiddenTicketIds.length})',
                onPressed: () {
                  setState(() => _showHidden = !_showHidden);
                  filterTKTATs();
                  setState(() {});
                },
                color: Colors.white,
                iconSize: 20,
              ),
            ),
          // زر إنشاء تذكرة جديدة
          Container(
            margin: EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: IconButton(
              icon: Icon(Icons.add_circle_outline, size: 20),
              tooltip: 'تذكرة جديدة',
              onPressed: () async {
                final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => CreateTicketPage(authToken: widget.authToken)));
                if (result == true && mounted) { setState(() => isLoading = true); fetchTKTATs(); }
              },
              color: Colors.white,
              iconSize: 20,
            ),
          ),
          // أيقونة الإشعارات الجديدة - إضافة جديدة
          Container(
            margin: EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Stack(
              children: [
                IconButton(
                  icon: Icon(Icons.notifications, size: 20),
                  tooltip: 'الإشعارات',
                  onPressed: _showNotificationsDialog,
                  color: Colors.white,
                  iconSize: 20,
                ),
                if (showNotificationBadge && newTicketsCount > 0)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      padding: EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.red[600],
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withValues(alpha: 0.5),
                            blurRadius: 4,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      constraints: BoxConstraints(
                        minWidth: 20,
                        minHeight: 20,
                      ),
                      child: Text(
                        newTicketsCount > 99
                            ? '99+'
                            : newTicketsCount.toString(),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            margin: EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'إعادة تحميل',
              onPressed: () async {
                setState(() => isLoading = true);
                await fetchTKTATs();
              },
              color: Colors.white,
              iconSize: 20,
            ),
          ),
          SizedBox(width: 8),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.blue[50]!, Colors.white],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            children: [
              // شريط اختيار نوع المهام (الكل / الشركة / الوكيل)
              _buildTaskTypeSelectorBar(),
              SizedBox(height: 8),
              // Filter Section
              if (isFilterVisible) _buildFilterSection(),

              // TKTAT List
              Expanded(child: _buildTKTATsList()),

              // Navigation Section
              _buildNavigationSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterSection() {
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue[600]!, Colors.blue[700]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.filter_alt, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text(
                  'تصفية TKTATs',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),

            // Search TextField - Smaller
            Container(
              height: 45,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                onChanged: (value) {
                  setState(() {
                    filterText = value;
                    filterTKTATs();
                  });
                },
                decoration: InputDecoration(
                  hintText: 'البحث في TKTATs...',
                  hintStyle: TextStyle(fontSize: 13, color: Colors.grey[500]),
                  prefixIcon:
                      Icon(Icons.search, color: Colors.blue[600], size: 20),
                  suffixIcon: filterText.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear, color: Colors.grey, size: 18),
                          onPressed: () {
                            setState(() {
                              filterText = "";
                              filterTKTATs();
                            });
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                style: TextStyle(fontSize: 14),
              ),
            ),

            SizedBox(height: 12),

            // Compact Task Type Selector with Icons
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              padding: EdgeInsets.all(4),
              child: Row(
                children: [
                  Expanded(
                    child: _buildCompactFilterButton(
                        'المفتوحة', 'open', Icons.pending_actions),
                  ),
                  SizedBox(width: 4),
                  Expanded(
                    child: _buildCompactFilterButton(
                        'الكل', 'all', Icons.all_inclusive),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactFilterButton(String title, String type, IconData icon) {
    final isSelected = selectedTicketType == type;
    return GestureDetector(
      onTap: () {
        if (selectedTicketType != type) {
          setState(() {
            selectedTicketType = type;
            currentPage = 1;
          });
          fetchTKTATs(); // إعادة جلب من السيرفر لأن الـ URL يتغير
        }
      },
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(colors: [Colors.white, Colors.grey[50]!])
              : null,
          color: isSelected ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color:
                isSelected ? Colors.white : Colors.white.withValues(alpha: 0.3),
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.blue[600] : Colors.white,
              size: 18,
            ),
            SizedBox(height: 2),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isSelected ? Colors.blue[600] : Colors.white,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTKTATsList() {
    if (!isLoading) {
      if (filteredTKTATs.isNotEmpty) {
        return RawScrollbar(
          controller: _listController,
          thumbVisibility: true,
          trackVisibility: true,
          thickness: 10,
          radius: const Radius.circular(12),
          interactive: true,
          thumbColor: const Color.fromARGB(255, 203, 85, 38),
          trackColor: Colors.indigo.shade50,
          trackBorderColor: Colors.indigo.shade100,
          child: ListView.builder(
            controller: _listController,
            itemCount: filteredTKTATs.length,
            itemBuilder: (context, index) {
              final tktat = filteredTKTATs[index];
              return _buildTKTATCard(tktat, index);
            },
          ),
        );
      } else {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withValues(alpha: 0.1),
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.assignment_outlined,
                      size: 60,
                      color: Colors.orange[400],
                    ),
                    SizedBox(height: 12),
                    GestureDetector(
                      onTap: lastErrorDetails != null
                          ? showErrorDetailsDialog
                          : null,
                      child: Container(
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red[50],
                          borderRadius: BorderRadius.circular(8),
                          border:
                              Border.all(color: Colors.red[200]!, width: 0.5),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                message.isNotEmpty
                                    ? message
                                    : "لا توجد TKTATs متاحة",
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.red[700],
                                  fontWeight: FontWeight.w500,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            if (lastErrorDetails != null) ...[
                              SizedBox(width: 6),
                              Icon(
                                Icons.touch_app,
                                color: Colors.red[600],
                                size: 16,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () {
                            fetchTKTATs();
                          },
                          icon: Icon(Icons.refresh, size: 16),
                          label: Text('إعادة المحاولة'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue[600],
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            textStyle: TextStyle(fontSize: 12),
                          ),
                        ),
                        if (lastErrorDetails != null) SizedBox(width: 8),
                        if (lastErrorDetails != null)
                          ElevatedButton.icon(
                            onPressed: showErrorDetailsDialog,
                            icon: Icon(Icons.info_outline, size: 16),
                            label: Text('التفاصيل'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red[600],
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              textStyle: TextStyle(fontSize: 12),
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
      }
    } else {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withValues(alpha: 0.1),
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  CircularProgressIndicator(
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Colors.blue[600]!),
                    strokeWidth: 2.5,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'جاري تحميل TKTATs...',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildTKTATCard(dynamic tktat, int index) {
    final status = tktat['status']?.toString() ?? '';
    final priority = tktat['priority']?.toString() ?? '';
    final createdAt = tktat['createdAt']?.toString() ?? '';
    // استخدام نفس طريقة جلب العنوان كما في صفحة التفاصيل
    final title = tktat['self']?['displayValue']?.toString() ??
        tktat['title']?.toString() ??
        tktat['subject']?.toString() ??
        tktat['name']?.toString() ??
        tktat['ticketTitle']?.toString() ??
        'بدون عنوان';
    final description = tktat['description']?.toString() ??
        tktat['summary']?.toString() ??
        tktat['details']?.toString() ??
        '';
    // استخدام نفس طريقة جلب العميل كما في صفحة التفاصيل
    final customerName = tktat['customer']?['displayValue']?.toString() ??
        tktat['customerName']?.toString() ??
        tktat['customer']?.toString() ??
        tktat['clientName']?.toString() ??
        tktat['client']?.toString() ??
        tktat['userName']?.toString() ??
        tktat['user']?.toString() ??
        '';
    // استخدام نفس طريقة جلب المنطقة كما في صفحة التفاصيل
    final zone = tktat['zone']?['displayValue']?.toString() ??
        tktat['zone']?.toString() ??
        tktat['region']?.toString() ??
        '';
    final idVal = tktat['id']?.toString() ?? '';
    final selfId =
        tktat['self'] is Map ? tktat['self']['id']?.toString() ?? '' : '';
    final displayId = () {
      final d = tktat['displayId'];
      if (d != null && d.toString().trim().isNotEmpty) return d.toString();
      if (selfId.isNotEmpty) return selfId;
      return idVal;
    }();
    final createdAtRaw = createdAt;
    final updatedAtRaw = tktat['updatedAt']?.toString() ?? '';
    String fmt(String raw) {
      if (raw.isEmpty) return '';
      try {
        final d = DateTime.parse(raw).toLocal();
        return '${d.month}/${d.day} ${d.hour}:${d.minute.toString().padLeft(2, '0')}';
      } catch (_) {
        return raw;
      }
    }

    // تدرج فاتح (درجات أزرق سماوي لطيف) مع تبديل بسيط لتمييز البطاقات
    final List<Color> lightSchemeA = [
      const Color(0xFFFAFCFF), // أفتح
      const Color(0xFFF5F9FE),
    ];
    final List<Color> lightSchemeB = [
      const Color(0xFFFDFEFF),
      const Color(0xFFF2F7FC),
    ];
    final useAlt = index.isOdd;
    final LinearGradient cardGradient = LinearGradient(
      colors: useAlt ? lightSchemeB : lightSchemeA,
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    );

    return Container(
      margin: EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        gradient: cardGradient,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Colors.blueGrey[400]!,
          width: 1.5,
        ),
      ),
      child: InkWell(
        onTap: () => navigateToTaskDetails(context, tktat),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with status and priority
              Row(
                children: [
                  Icon(
                    getStatusIcon(status),
                    color: getStatusColor(status),
                    size: 17,
                  ),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      translateStatus(status),
                      style: TextStyle(
                        color: Colors.red,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // المعرف بجانب الحالة مع إمكانية النسخ
                  if (displayId.isNotEmpty) ...[
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      margin: EdgeInsets.only(left: 6),
                      decoration: BoxDecoration(
                        color: Colors.indigo.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: InkWell(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: displayId));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('تم نسخ المعرف: $displayId'),
                              backgroundColor: Colors.indigo[600],
                              duration: Duration(seconds: 1),
                            ),
                          );
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.copy, size: 13, color: Colors.indigo[500]),
                            SizedBox(width: 3),
                            Text(
                              displayId,
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.indigo[600]),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (priority.isNotEmpty)
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: getPriorityColor(priority),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        translatePriority(priority),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  SizedBox(width: 4),
                  // زر إخفاء/إظهار التذكرة
                  InkWell(
                    onTap: () {
                      final tId = selfId.isNotEmpty ? selfId : idVal;
                      if (tId.isNotEmpty) _toggleHideTicket(tId);
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      decoration: BoxDecoration(
                        color: _hiddenTicketIds.contains(selfId.isNotEmpty ? selfId : idVal)
                            ? Colors.orange.withValues(alpha: 0.15)
                            : Colors.grey.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        _hiddenTicketIds.contains(selfId.isNotEmpty ? selfId : idVal)
                            ? Icons.visibility
                            : Icons.visibility_off,
                        size: 16,
                        color: _hiddenTicketIds.contains(selfId.isNotEmpty ? selfId : idVal)
                            ? Colors.orange[700]
                            : Colors.grey[600],
                      ),
                    ),
                  ),
                  SizedBox(width: 4),
                  InkWell(
                    onTap: () {
                      try {
                        navigateToTaskDetails(context, tktat);
                      } catch (e) {
                        showInAppNotification('تعذر فتح التفاصيل',
                            backgroundColor: Colors.red[600]);
                      }
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Color(0xFF1565C0),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.open_in_new, size: 15, color: Colors.white),
                          SizedBox(width: 3),
                          Text('فتح', style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              SizedBox(height: 6),

              // العنوان
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: Color(0xFFE3F2FD),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Color(0xFF90CAF9), width: 0.8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.title, size: 16, color: Colors.blue[700]),
                    SizedBox(width: 6),
                    Expanded(
                      child: SelectableText(
                        title,
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.blueGrey[900], height: 1.15),
                        maxLines: 1,
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: title));
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم نسخ العنوان'), duration: Duration(seconds: 1)));
                      },
                      child: Icon(Icons.copy, size: 15, color: Colors.blue[400]),
                    ),
                  ],
                ),
              ),

              // الملخص
              if (description.isNotEmpty) ...[
                SizedBox(height: 3),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: Color(0xFFE8FFF5),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Color(0xFF80CBC4), width: 0.8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.notes, size: 16, color: Colors.teal[700]),
                      SizedBox(width: 6),
                      Expanded(
                        child: SelectableText(
                          description,
                          style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: Colors.teal[900], height: 1.2),
                          maxLines: 2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              SizedBox(height: 4),

              // صف العميل والمنطقة
              Row(
                children: [
                  if (customerName.isNotEmpty)
                    Expanded(
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: Color(0xFFFFF3E0),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Color(0xFFFFCC80), width: 0.8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.person, size: 16, color: Colors.orange[700]),
                            SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                customerName,
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.brown[800]),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            InkWell(
                              onTap: () {
                                Clipboard.setData(ClipboardData(text: customerName));
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('نُسخ اسم العميل'), duration: Duration(seconds: 1)));
                              },
                              child: Icon(Icons.copy, size: 15, color: Colors.orange[400]),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (customerName.isNotEmpty && zone.isNotEmpty)
                    SizedBox(width: 6),
                  if (zone.isNotEmpty)
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: Color(0xFFEDE7F6),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Color(0xFFB39DDB), width: 0.8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.location_on, size: 15, color: Colors.indigo[600]),
                          SizedBox(width: 3),
                          Text(zone, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.indigo[800])),
                        ],
                      ),
                    ),
                ],
              ),

              SizedBox(height: 4),

              // التواريخ والنوع
              if (createdAtRaw.isNotEmpty || updatedAtRaw.isNotEmpty || status.isNotEmpty)
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    if (createdAtRaw.isNotEmpty)
                      _buildTimeInfoChip(icon: Icons.schedule, label: 'إنشاء', value: fmt(createdAtRaw), color: Colors.blueGrey),
                    if (updatedAtRaw.isNotEmpty)
                      _buildTimeInfoChip(icon: Icons.update, label: 'تحديث', value: fmt(updatedAtRaw), color: Colors.deepOrange),
                  ],
                ),

              // (أزيل صف نوع المهمة بعد دمجه مع صف الوقت)

              // إضافة معلومات debug إذا لم يكن العنوان يظهر
              if (title == 'بدون عنوان') ...[
                SizedBox(height: 8),
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.red[200]!, width: 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'بيانات debug - العنوان غير موجود',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.red[600],
                        ),
                      ),
                      SizedBox(height: 4),
                      SelectableText(
                        'الحقول المتاحة: ${tktat.keys.toList()}\n'
                        'self.displayValue: ${tktat['self']?['displayValue']}\n'
                        'title: ${tktat['title']}\n'
                        'subject: ${tktat['subject']}',
                        style: TextStyle(
                          fontSize: 9,
                          color: Colors.red[500],
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // عنصر مساعد لعرض شريحة وقت/معرّف واضحة
  Widget _buildTimeInfoChip(
      {required IconData icon,
      required String label,
      required String value,
      required Color color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        SizedBox(width: 3),
        Text(
          '$label: $value',
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: color.darken(0.1)),
        ),
      ],
    );
  }

  // حوار يعرض جميع الحقول الخام للتذكرة
  void showTicketRawDialog(Map<String, dynamic> ticket) {
    // ترتيب المفاتيح أبجدياً لتسهيل القراءة
    final keys = ticket.keys.toList()..sort();

    // إنشاء JSON جميل (محاولة تبسيط القيم)
    String prettyJson() {
      dynamic simplify(dynamic v) {
        if (v is Map) {
          return v.map((k, val) => MapEntry(k.toString(), simplify(val)));
        } else if (v is List) {
          return v.map(simplify).toList();
        } else {
          return v;
        }
      }

      try {
        final simplified = simplify(ticket);
        const encoder = JsonEncoder.withIndent('  ');
        return encoder.convert(simplified);
      } catch (_) {
        return ticket.toString();
      }
    }

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 40),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            constraints: BoxConstraints(
              maxWidth: (MediaQuery.of(context).size.width - 40).clamp(280.0, 480.0),
            ),
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.data_object, color: Colors.blue[600]),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'الحقول الخام للتذكرة',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      tooltip: 'نسخ كل JSON',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: prettyJson()));
                        Navigator.pop(context);
                        showInAppNotification('تم نسخ JSON');
                      },
                      icon: Icon(Icons.copy, size: 18),
                    ),
                    IconButton(
                      tooltip: 'إغلاق',
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close),
                    )
                  ],
                ),
                SizedBox(height: 8),
                Expanded(
                  child: DefaultTabController(
                    length: 2,
                    child: Column(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.blueGrey[50],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: TabBar(
                            labelColor: Colors.blue[700],
                            unselectedLabelColor: Colors.blueGrey[400],
                            indicator: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 4,
                                )
                              ],
                            ),
                            tabs: [
                              Tab(text: 'مفاتيح'),
                              Tab(text: 'JSON'),
                            ],
                          ),
                        ),
                        SizedBox(height: 8),
                        Expanded(
                          child: TabBarView(
                            children: [
                              // تبويب المفاتيح والقيم
                              Scrollbar(
                                child: ListView.builder(
                                  itemCount: keys.length,
                                  itemBuilder: (context, i) {
                                    final k = keys[i];
                                    final v = ticket[k];
                                    String shortVal;
                                    if (v is Map) {
                                      shortVal =
                                          v['displayValue']?.toString() ??
                                              v.keys.join(', ');
                                    } else if (v is List) {
                                      shortVal = '[${v.length} عناصر]';
                                    } else {
                                      shortVal = v?.toString() ?? 'null';
                                    }
                                    return Container(
                                      margin: EdgeInsets.only(bottom: 6),
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: Colors.grey[50],
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                            color: Colors.grey[200]!),
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
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
                                          SizedBox(width: 8),
                                          Expanded(
                                            flex: 7,
                                            child: SelectableText(
                                              shortVal,
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.blueGrey[800]),
                                              maxLines: 4,
                                            ),
                                          ),
                                          InkWell(
                                            onTap: () {
                                              Clipboard.setData(ClipboardData(
                                                  text: shortVal));
                                              showInAppNotification(
                                                  'نُسخت القيمة: $k');
                                            },
                                            child: Padding(
                                              padding: EdgeInsets.all(4),
                                              child: Icon(Icons.copy,
                                                  size: 14,
                                                  color: Colors.blueGrey[400]),
                                            ),
                                          )
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                              // تبويب JSON الكامل
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.black,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                padding: EdgeInsets.all(10),
                                child: Scrollbar(
                                  child: SingleChildScrollView(
                                    child: SelectableText(
                                      prettyJson(),
                                      style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 11.5,
                                        color: Colors.greenAccent[100],
                                        height: 1.25,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildNavigationSection() {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      padding: EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.white, Colors.grey[50]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            blurRadius: 6,
            offset: Offset(0, -1),
          ),
        ],
        border: Border.all(
          color: Colors.grey.withValues(alpha: 0.1),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Previous Button - Compact
          _buildCompactNavButton(
            onPressed: currentPage > 1 ? previousPage : null,
            icon: Icons.chevron_right,
            label: 'السابق',
            isEnabled: currentPage > 1,
          ),

          // Page Info - Enhanced
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.blue.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'ص $currentPage',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[700],
                  ),
                ),
                if (totalTKTATs > 0)
                  Text(
                    '${filteredTKTATs.length} من $totalTKTATs',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey[600],
                    ),
                  ),
              ],
            ),
          ),

          // Next Button - Compact
          _buildCompactNavButton(
            onPressed: nextPage,
            icon: Icons.chevron_left,
            label: 'التالي',
            isEnabled: true,
          ),
        ],
      ),
    );
  }

  Widget _buildCompactNavButton({
    required VoidCallback? onPressed,
    required IconData icon,
    required String label,
    required bool isEnabled,
  }) {
    return SizedBox(
      height: 36,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: isEnabled ? Colors.blue[600] : Colors.grey[300],
          foregroundColor: Colors.white,
          elevation: isEnabled ? 2 : 0,
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          minimumSize: Size(70, 36),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16),
            SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // إشعار النظام محسّن للمهام الجديدة
  Future<void> showEnhancedNotification(
      int count, List<Map<String, dynamic>> newTasks) async {
    try {
      String title = 'مهام جديدة متاحة! 🔔';
      String body;

      if (count == 1) {
        final taskTitle = newTasks[0]['self']?['displayValue']?.toString() ??
            newTasks[0]['title']?.toString() ??
            'مهمة جديدة';
        body = 'وصلت مهمة جديدة: $taskTitle';
      } else {
        body = 'وصل $count مهام جديدة تحتاج للمراجعة';
      }

      final AndroidNotificationDetails androidPlatformChannelSpecifics =
          AndroidNotificationDetails(
        'new_tktats_channel',
        'مهام جديدة',
        channelDescription: 'إشعارات المهام الجديدة في FTTH',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        enableVibration: true,
        playSound: true,
        icon: '@mipmap/ic_launcher',
        color: Color(0xFF4CAF50), // لون أخضر للمهام الجديدة
        ticker: 'مهام جديدة وصلت',
        styleInformation: BigTextStyleInformation(
          body,
          contentTitle: title,
          summaryText: 'نظام FTTH - $count مهام جديدة',
        ),
        // إضافة صوت مخصص
        sound: RawResourceAndroidNotificationSound('notification'),
        // إضافة أضواء LED
        enableLights: true,
        ledColor: Color(0xFF4CAF50),
        ledOnMs: 1000,
        ledOffMs: 500,
      );

      const DarwinNotificationDetails iOSPlatformChannelSpecifics =
          DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'default',
        badgeNumber: 1,
      );

      final NotificationDetails platformChannelSpecifics = NotificationDetails(
        android: androidPlatformChannelSpecifics,
        iOS: iOSPlatformChannelSpecifics,
      );

      await localNotificationsPlugin.show(
        DateTime.now().millisecondsSinceEpoch.remainder(100000),
        title,
        body,
        platformChannelSpecifics,
        payload: 'new_tktats_$count',
      );

      debugPrint('✅ تم إرسال إشعار النظام بنجاح');
    } catch (e) {
      debugPrint('❌ خطأ في إرسال إشعار النظام');
    }
  }

  // إشعار داخل التطبيق محسّن
  Future<void> showEnhancedInAppNotification(
      int count, List<Map<String, dynamic>> newTasks) async {
    if (!mounted) return;

    String message;
    String actionText = 'عرض';

    if (count == 1) {
      final taskTitle = newTasks[0]['self']?['displayValue']?.toString() ??
          newTasks[0]['title']?.toString() ??
          'مهمة جديدة';
      final customerName =
          newTasks[0]['customer']?['displayValue']?.toString() ?? '';

      if (customerName.isNotEmpty) {
        message = '🎯 مهمة جديدة من: $customerName\n📋 $taskTitle';
      } else {
        message = '🎯 مهمة جديدة: $taskTitle';
      }
    } else {
      message = '🔔 وصل $count مهام جديدة تحتاج للمراجعة';
      actionText = 'عرض الكل';
    }

    // تحديث عداد الإشعارات
    setState(() {
      newTicketsCount = count;
      showNotificationBadge = true;
    });

    // إظهار إشعار مطور داخل التطبيق
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Container(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      Icons.notification_important,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'مهام جديدة وصلت!',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          message,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withValues(alpha: 0.9),
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        backgroundColor: Color(0xFF4CAF50),
        duration: Duration(seconds: 6),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: EdgeInsets.all(16),
        elevation: 6,
        action: SnackBarAction(
          label: actionText,
          textColor: Colors.white,
          backgroundColor: Colors.white.withValues(alpha: 0.2),
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            // تحديث القائمة لإظهار المهام الجديدة
            setState(() {
              selectedTicketType = 'all';
              filterText = '';
            });
            filterTKTATs();
          },
        ),
      ),
    );

    // إضافة اهتزاز خفيف (إذا كان متاحاً)
    try {
      HapticFeedback.lightImpact();
    } catch (e) {
      debugPrint('Haptic feedback not available');
    }
  }

  // دالة إظهار حوار الإشعارات
  void _showNotificationsDialog() {
    // إخفاء عداد الإشعارات عند فتح الحوار
    setState(() {
      showNotificationBadge = false;
      newTicketsCount = 0;
    });

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.notifications, color: Colors.blue[600]),
              SizedBox(width: 8),
              Text('الإشعارات'),
              Spacer(),
              IconButton(
                icon: Icon(Icons.refresh, size: 20),
                tooltip: 'تحديث',
                onPressed: () {
                  Navigator.of(context).pop();
                  fetchTKTATs(showNotificationOnNewTKTATs: true);
                },
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: min(400, MediaQuery.of(context).size.height * 0.6),
            child: Column(
              children: [
                // إحصائيات سريعة
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.blue[50]!, Colors.blue[100]!],
                    ),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildNotificationStat(
                        'إجمالي التذاكر',
                        totalTKTATs.toString(),
                        Icons.assignment,
                        Colors.blue[600]!,
                      ),
                      Container(width: 1, height: 30, color: Colors.blue[300]),
                      _buildNotificationStat(
                        'التذاكر المعروضة',
                        filteredTKTATs.length.toString(),
                        Icons.visibility,
                        Colors.green[600]!,
                      ),
                      Container(width: 1, height: 30, color: Colors.blue[300]),
                      _buildNotificationStat(
                        'الصفحة الحالية',
                        currentPage.toString(),
                        Icons.pages,
                        Colors.orange[600]!,
                      ),
                    ],
                  ),
                ),

                SizedBox(height: 16),

                // قائمة الإشعارات
                Expanded(
                  child: filteredTKTATs.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.notifications_none,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              SizedBox(height: 16),
                              Text(
                                'لا توجد تذاكر للعرض',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'جميع التذاكر محدثة!',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: filteredTKTATs.length > 5
                              ? 5
                              : filteredTKTATs.length,
                          itemBuilder: (context, index) {
                            final ticket = filteredTKTATs[index];
                            final title =
                                ticket['self']?['displayValue']?.toString() ??
                                    ticket['title']?.toString() ??
                                    'تذكرة جديدة';
                            final customerName = ticket['customer']
                                        ?['displayValue']
                                    ?.toString() ??
                                '';
                            final status = ticket['status']?.toString() ?? '';
                            final createdAt =
                                ticket['createdAt']?.toString() ?? '';

                            return Card(
                              margin: EdgeInsets.only(bottom: 8),
                              elevation: 2,
                              child: ListTile(
                                leading: Container(
                                  padding: EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: getStatusColor(status)
                                        .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    getStatusIcon(status),
                                    color: getStatusColor(status),
                                    size: 20,
                                  ),
                                ),
                                title: Text(
                                  title,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (customerName.isNotEmpty) ...[
                                      SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Icon(Icons.person,
                                              size: 12,
                                              color: Colors.grey[600]),
                                          SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              customerName,
                                              style: TextStyle(fontSize: 12),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                    if (createdAt.isNotEmpty) ...[
                                      SizedBox(height: 2),
                                      Row(
                                        children: [
                                          Icon(Icons.access_time,
                                              size: 12,
                                              color: Colors.grey[600]),
                                          SizedBox(width: 4),
                                          Text(
                                            formatDate(createdAt),
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey[600]),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                                trailing: Container(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    translateStatus(status),
                                    style: TextStyle(
                                      color: Colors.red,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                onTap: () {
                                  Navigator.of(context).pop();
                                  navigateToTaskDetails(context, ticket);
                                },
                              ),
                            );
                          },
                        ),
                ),

                // إظهار رسالة إذا كان هناك المزيد من التذاكر
                if (filteredTKTATs.length > 5) ...[
                  SizedBox(height: 8),
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue[200]!),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.info_outline,
                            size: 16, color: Colors.blue[600]),
                        SizedBox(width: 8),
                        Text(
                          'يوجد ${filteredTKTATs.length - 5} تذاكر إضافية',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                setState(() {
                  selectedTicketType = 'all';
                  filterText = '';
                });
                filterTKTATs();
              },
              icon: Icon(Icons.list, size: 16),
              label: Text('عرض الكل'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('إغلاق'),
            ),
          ],
        );
      },
    );
  }

  // دالة مساعدة لبناء إحصائية في حوار الإشعارات
  Widget _buildNotificationStat(
      String label, String value, IconData icon, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 20),
        SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey[600],
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  // (تم الاستبدال ببطاقة موحدة _buildCountCard)

  // بطاقة موحدة للنص + العدد
  Widget _buildCountCard() {
    return AnimatedSwitcher(
      duration: Duration(milliseconds: 260),
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1).animate(anim),
            child: child),
      ),
      child: Container(
        key: ValueKey(
            'card-${filteredTKTATs.length}-$totalTKTATs-$selectedTicketType'),
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.white.withValues(alpha: 0.95),
              Colors.white.withValues(alpha: 0.88),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 10,
              offset: Offset(0, 3),
            ),
          ],
          border:
              Border.all(color: Colors.white.withValues(alpha: 0.75), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.blue[600]!,
                    Colors.indigo[500]!,
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.withValues(alpha: 0.35),
                    blurRadius: 6,
                    offset: Offset(0, 3),
                  )
                ],
              ),
              child: Icon(Icons.task_alt, color: Colors.white, size: 18),
            ),
            SizedBox(width: 10),
            Text(
              'العدد',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.blueGrey[800],
                letterSpacing: .4,
              ),
            ),
            SizedBox(width: 12),
            Container(
              height: 26,
              width: 1.2,
              decoration: BoxDecoration(
                color: Colors.blueGrey[200],
                borderRadius: BorderRadius.circular(1),
              ),
            ),
            SizedBox(width: 12),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${filteredTKTATs.length}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.blue[800],
                    height: 1,
                  ),
                ),
                if (selectedTicketType == 'all' &&
                    totalTKTATs > filteredTKTATs.length) ...[
                  SizedBox(width: 4),
                  Text(
                    '/ $totalTKTATs',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.blueGrey[600],
                      height: 1,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  // شريط علوي أسفل الـ AppBar لاختيار نوع المهام
  Widget _buildTaskTypeSelectorBar() {
    final types = [
      {
        'label': 'المفتوحة',
        'type': 'open',
        'icon': Icons.pending_actions,
        'color': const Color.fromARGB(255, 57, 113, 191)
      },
      {
        'label': 'الكل',
        'type': 'all',
        'icon': Icons.all_inclusive,
        'color': Colors.teal
      },
    ];
    // لا حاجة للمؤشر الآن بعد حذفه

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 6.0;

        return Container(
          height: 60,
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.blue[600]!,
                Colors.indigo[500]!,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.blue.withValues(alpha: 0.25),
                blurRadius: 18,
                offset: Offset(0, 6),
              ),
            ],
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.18), width: 1),
          ),
          child: Row(
            children: [
              for (var i = 0; i < types.length; i++) ...[
                Expanded(
                  child: _buildTopSelectorButton(
                    label: types[i]['label'] as String,
                    type: types[i]['type'] as String,
                    icon: types[i]['icon'] as IconData,
                    activeColor: types[i]['color'] as Color,
                  ),
                ),
                if (i != types.length - 1) SizedBox(width: gap),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildTopSelectorButton({
    required String label,
    required String type,
    required IconData icon,
    required Color activeColor,
  }) {
    final bool active = selectedTicketType == type;
    return Expanded(
      child: AnimatedContainer(
        duration: Duration(milliseconds: 220),
        curve: Curves.easeOut,
        height: 44,
        decoration: BoxDecoration(
          // تصميم جديد: زر نشط بتدرج واضح، زر غير نشط بخلفية شفافة فاتحة
          gradient: active
              ? LinearGradient(
                  colors: [
                    Colors.green[600]!.withValues(alpha: 0.95),
                    Colors.green[400]!.withValues(alpha: 0.80),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: active ? null : Colors.white, // الزر غير النشط أبيض
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active
                ? Colors.green[700]!.withValues(alpha: 0.9)
                : activeColor
                    .withValues(alpha: 0.55), // حدود ملوّنة خفيفة للحالة غير النشطة
            width: active ? 1.4 : 1,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: Colors.green[600]!.withValues(alpha: 0.45),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              if (selectedTicketType == type) return;
              setState(() {
                selectedTicketType = type;
                currentPage = 1;
              });
              fetchTKTATs(); // إعادة جلب من السيرفر لأن الـ URL يتغير
              HapticFeedback.selectionClick();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      Icon(icon, color: activeColor, size: 18),
                      SizedBox(width: 8),
                      Text(
                          'تم عرض ${label == 'الكل' ? 'جميع المهام' : 'مهام $label'}'),
                      Spacer(),
                      Text('${filteredTKTATs.length}',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  backgroundColor: activeColor.withValues(alpha: 0.9),
                  duration: Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              );
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    size: 20,
                    color:
                        active ? Colors.white : activeColor.withValues(alpha: 0.9)),
                SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    letterSpacing: .3,
                    color: active ? Colors.white : activeColor.darken(0.05),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // _buildMetaChip أزيل لأنه لم يعد مستخدماً بعد إعادة التصميم
}
