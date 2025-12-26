/// اسم الصفحة: تفاصيل العدادات
/// وصف الصفحة: صفحة تفاصيل العدادات ومعلوماتها
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:excel/excel.dart' as excel;
import '../../services/permissions_service.dart';
import '../../services/auth_service.dart';

class CaounterDetailsPage extends StatefulWidget {
  final String authToken;
  final String username;
  const CaounterDetailsPage(
      {super.key, required this.authToken, required this.username});

  @override
  State<CaounterDetailsPage> createState() => _CaounterDetailsPageState();
}

class _CaounterDetailsPageState extends State<CaounterDetailsPage> {
  bool isLoading = true;
  int _totalCount = 0;
  List<dynamic> _auditLogs = [];
  List<String> _zones = [];
  List<String> _eventTypes = [];
  String? _selectedZone;
  List<String> _selectedEventTypes = []; // قائمة لاختيار عدة أنواع أحداث
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _fromDateController = TextEditingController();
  final TextEditingController _toDateController = TextEditingController();
  String message = "";
  double _totalAmount = 0.0;
  // متغير عام لإظهار / إخفاء البيانات الخام لكل العناصر
  bool _showRaw = false;

  // متغيرات رصيد المحفظة
  double _walletBalance = 0.0;
  double _commission = 0.0;
  bool _hasTeamMemberWallet = false;
  double _teamMemberWalletBalance = 0.0;
  String? _partnerId;
  bool _walletDataLoaded = false;

  // دالة للتحقق من وجود فلاتر نشطة
  bool get hasActiveFilters {
    return _selectedZone != null ||
        _selectedEventTypes.isNotEmpty ||
        _usernameController.text.isNotEmpty ||
        _fromDateController.text.isNotEmpty ||
        _toDateController.text.isNotEmpty;
  }

  int _currentPage = 1;
  int _totalPages = 1;
  final int _pageSize = 100; // عرض آخر 100 سجل

  // ضع رابط سكريبت جوجل للتطبيقات هنا
  final String googleScriptUrl =
      "https://script.google.com/macros/s/AKfycbyK7m9s6W-oGJgCbN80aP_Ea9z7Ar-I02tjbAR7S6CxYMbv30nwbuCKsRjh_1FtXAzMbA/exec";

  @override
  void initState() {
    super.initState();
    _initializePartnerId();
    fetchAuditLogs();
    _fetchZones();
    fetchSummary();
    _eventTypes = [
      // أحداث الاشتراكات
      "ChangeSubscription",
      "ExtendSubscription",
      "PurchaseSubscriptionFromTrial",
      "PLAN_CHANGE",
      "PLAN_PURCHASE",
      "PLAN_RENEW",
      "PLAN_CANCEL",
      "PLAN_UPGRADE",
      "PLAN_DOWNGRADE",
      "PLAN_EXTEND",
      "PLAN_REACTIVATE",
      "PLAN_SCHEDULE",

      // أحداث المحفظة
      "WALLET_TOPUP",
      "WALLET_TRANSFER",
      "WALLET_REVERSAL",
      "WALLET_ADJUST",
      "WALLET_REFUND",
      "RefillTeamMemberWallet",

      // أحداث الدفع
      "PAYMENT",
      "PAYMENT_REVERSAL",

      // أحداث الخصومات
      "DISCOUNT_APPLY",
      "DISCOUNT_REVOKE",

      // أحداث النظام
      "CreateToken",
      "SCHEDULE_CHANGE",
      "TRIAL_PERIOD",
      "AUTO_RENEW",
    ];
  }

  Future<void> _initializePartnerId() async {
    try {
      final response = await AuthService.instance.authenticatedRequest(
        'GET',
        'https://admin.ftth.iq/api/auth/me',
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final partnerId = data['user']?['partner']?['self']?['id']?.toString();
        if (partnerId != null && partnerId.isNotEmpty) {
          setState(() {
            _partnerId = partnerId;
          });
          // جلب رصيد المحفظة بعد الحصول على partnerId
          await _fetchWalletBalance();
        }
      }
    } catch (e) {
      print('خطأ في جلب بيانات الشريك: $e');
    }
  }

  // دالة جلب رصيد المحفظة من المصدر
  Future<void> _fetchWalletBalance() async {
    if (_partnerId == null) return;

    try {
      final response = await AuthService.instance.authenticatedRequest(
        'GET',
        'https://api.ftth.iq/api/partners/$_partnerId/wallets/balance',
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final model = data['model'] ?? {};

        if (mounted) {
          setState(() {
            _walletBalance = (model['balance'] ?? 0.0).toDouble();
            _commission = (model['commission'] ?? 0.0).toDouble();

            final tmw = model['teamMemberWallet'];
            if (tmw != null) {
              _teamMemberWalletBalance = (tmw['balance'] ?? 0.0).toDouble();
              _hasTeamMemberWallet = tmw['hasWallet'] == true;
            } else {
              _teamMemberWalletBalance = 0.0;
              _hasTeamMemberWallet = false;
            }

            _walletDataLoaded = true;
          });
        }
      } else {
        print('فشل في جلب رصيد المحفظة: ${response.statusCode}');
      }
    } catch (e) {
      print('خطأ في جلب رصيد المحفظة: $e');
    }
  }

  // دالة لجلب رصيد محفظة العميل
  Future<Map<String, dynamic>?> _fetchCustomerWalletBalance(
      String customerId) async {
    try {
      final response = await AuthService.instance.authenticatedRequest(
        'GET',
        'https://api.ftth.iq/api/customers/$customerId/wallets/balance',
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print('خطأ في جلب رصيد محفظة العميل: $e');
    }
    return null;
  }

  Future<void> _fetchZones() async {
    try {
      final url = Uri.parse('https://api.ftth.iq/api/locations/zones');
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer ${widget.authToken}',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _zones = (data['items'] ?? [])
              .map<String>((zone) =>
                  zone['self']['displayValue']?.toString() ?? 'غير معروف')
              .toList();
          _zones.sort();
        });
      } else if (response.statusCode == 403) {
        setState(() {
          message =
              "تم رفض الوصول: يبدو أنك لا تمتلك الصلاحيات اللازمة لعرض البيانات. الرجاء مراجعة الصلاحيات.";
          _zones = [
            'بيانات افتراضية 1',
            'بيانات افتراضية 2',
            'بيانات افتراضية 3'
          ];
        });
      } else {
        setState(() {
          message =
              "فشل جلب المناطق: ${response.statusCode} - ${response.body}";
        });
      }
    } catch (e) {
      setState(() {
        message = "حدث خطأ أثناء جلب المناطق: $e";
      });
    }
  }

  Future<void> fetchSummary() async {
    try {
      String toDate = _toDateController.text;
      if (toDate.isNotEmpty) {
        toDate = "${toDate.split('T')[0]}T23:59:59";
      }

      // بناء الـ query parameters بشكل صحيح للملخص
      Map<String, String> queryParams = {};

      if (_selectedZone != null && _selectedZone!.isNotEmpty) {
        queryParams['zoneIds'] = _selectedZone!;
      }
      if (_selectedEventTypes.isNotEmpty) {
        queryParams['eventTypes'] = _selectedEventTypes.join(',');
      }
      if (_usernameController.text.isNotEmpty) {
        queryParams['username'] = _usernameController.text.trim();
      }
      if (_fromDateController.text.isNotEmpty) {
        queryParams['createdAt.from'] = _fromDateController.text;
      }
      if (toDate.isNotEmpty && _toDateController.text.isNotEmpty) {
        queryParams['createdAt.to'] = toDate;
      }

      final url =
          Uri.https('api.ftth.iq', '/api/audit-logs/summary', queryParams);

      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer ${widget.authToken}',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _totalAmount = data['model']['totalAmount'] ?? 0.0;
        });
      } else {
        throw Exception('فشل في جلب بيانات الملخص: ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        message = "حدث خطأ أثناء جلب بيانات الملخص: $e";
      });
    }
  }

  String translateEventType(String eventType) {
    const eventTranslations = {
      // أحداث الاشتراكات
      "ChangeSubscription": "🔄 تغيير الاشتراك",
      "ExtendSubscription": "📅 تمديد الاشتراك",
      "PurchaseSubscriptionFromTrial": "🛒 شراء من التجريبي",
      "PLAN_CHANGE": "🔄 تغيير الخطة",
      "PLAN_PURCHASE": "🛒 شراء الخطة",
      "PLAN_RENEW": "🔄 تجديد الخطة",
      "PLAN_CANCEL": "❌ إلغاء الخطة",
      "PLAN_UPGRADE": "⬆️ ترقية الخطة",
      "PLAN_DOWNGRADE": "⬇️ خفض الخطة",
      "PLAN_EXTEND": "📅 تمديد الخطة",
      "PLAN_REACTIVATE": "🔄 إعادة تفعيل الخطة",
      "PLAN_SCHEDULE": "📅 جدولة الخطة",

      // أحداث المحفظة
      "WALLET_TOPUP": "💳 شحن المحفظة",
      "WALLET_TRANSFER": "💸 تحويل محفظة",
      "WALLET_REVERSAL": "🔄 عكس محفظة",
      "WALLET_ADJUST": "⚖️ تعديل محفظة",
      "WALLET_REFUND": "💰 استرجاع محفظة",
      "RefillTeamMemberWallet": "👥 شحن محفظة عضو فريق",

      // أحداث الدفع
      "PAYMENT": "💰 دفعة",
      "PAYMENT_REVERSAL": "🔄 عكس دفعة",

      // أحداث الخصومات
      "DISCOUNT_APPLY": "🎫 تطبيق خصم",
      "DISCOUNT_REVOKE": "❌ إلغاء خصم",

      // أحداث النظام
      "CreateToken": "🔐 إنشاء رمز مميز",
      "SCHEDULE_CHANGE": "📅 تغيير الجدولة",
      "TRIAL_PERIOD": "🆓 فترة تجريبية",
      "AUTO_RENEW": "🔄 تجديد تلقائي",
    };
    return eventTranslations[eventType] ?? eventType;
  }

  Future<Map<String, dynamic>> fetchAuditLogs() async {
    String toDate = _toDateController.text;
    if (toDate.isNotEmpty) {
      toDate = "${toDate.split('T')[0]}T23:59:59";
    }

    // بناء الـ query parameters بشكل صحيح
    Map<String, String> queryParams = {
      'pageSize': _pageSize.toString(),
      'pageNumber': _currentPage.toString(),
      'sortCriteria.property': 'CreatedAt',
      'sortCriteria.direction': 'desc',
    };

    // إضافة الفلاتر فقط إذا كانت غير فارغة
    if (_selectedZone != null && _selectedZone!.isNotEmpty) {
      queryParams['zoneIds'] = _selectedZone!;
    }
    if (_selectedEventTypes.isNotEmpty) {
      queryParams['eventTypes'] = _selectedEventTypes.join(',');
    }
    if (_usernameController.text.isNotEmpty) {
      queryParams['username'] = _usernameController.text.trim();
    }
    if (_fromDateController.text.isNotEmpty) {
      queryParams['createdAt.from'] = _fromDateController.text;
    }
    if (toDate.isNotEmpty && _toDateController.text.isNotEmpty) {
      queryParams['createdAt.to'] = toDate;
    }

    final url = Uri.https('api.ftth.iq', '/api/audit-logs', queryParams);

    // طباعة تشخيصية للفلاتر
    print('🔍 تشخيص - الفلاتر المطبقة:');
    print('   المنطقة: ${_selectedZone ?? 'لا يوجد'}');
    print(
        '   أنواع الأحداث: ${_selectedEventTypes.isEmpty ? 'لا يوجد' : _selectedEventTypes.join(', ')}');
    print(
        '   اسم المستخدم: ${_usernameController.text.isEmpty ? 'لا يوجد' : _usernameController.text}');
    print(
        '   تاريخ البداية: ${_fromDateController.text.isEmpty ? 'لا يوجد' : _fromDateController.text}');
    print(
        '   تاريخ النهاية: ${_toDateController.text.isEmpty ? 'لا يوجد' : _toDateController.text}');
    print('   الرابط الكامل: ${url.toString()}');

    try {
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer ${widget.authToken}',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('✅ استجابة الواجهة البرمجية: ${response.statusCode}');
        print('📊 العدد الإجمالي: ${data['totalCount']}');
        print('📝 عدد العناصر: ${(data['items'] as List?)?.length ?? 0}');

        setState(() {
          isLoading = false;
          _totalCount = data['totalCount'] ?? 0;
          _auditLogs = (data['items'] is List) ? data['items'] : [];
          _totalPages = (_totalCount / _pageSize).ceil().clamp(1, 999999);

          // رسالة تأكيد للتصفية
          if (hasActiveFilters && _totalCount == 0) {
            message =
                "❌ لم يتم العثور على نتائج تطابق الفلاتر المحددة. جرب تغيير الفلاتر.";
          } else if (hasActiveFilters && _totalCount > 0) {
            message =
                "✅ تم العثور على $_totalCount نتيجة تطابق الفلاتر المحددة.";
          } else {
            message = ""; // مسح أي رسالة سابقة عند النجاح
          }
        });
        return data;
      }

      // معالجة الأخطاء الشائعة
      print('❌ خطأ في الواجهة البرمجية: ${response.statusCode}');
      print('📝 محتوى الاستجابة: ${response.body}');

      String friendly;
      switch (response.statusCode) {
        case 401:
          friendly = 'غير مصرح: انتهت صلاحية الجلسة أو التوكن غير صالح.';
          break;
        case 403:
          friendly = 'لا تملك صلاحية للوصول إلى السجلات (403).';
          break;
        case 404:
          friendly = 'المورد غير موجود (404).';
          break;
        case 500:
          friendly = 'خطأ خادم داخلي (500)، حاول لاحقاً.';
          break;
        default:
          friendly = 'فشل في جلب البيانات: ${response.statusCode}';
      }
      setState(() {
        isLoading = false;
        _auditLogs = [];
        _totalCount = 0;
        _totalPages = 1;
        if (message.isEmpty ||
            message.startsWith('فشل') ||
            message.startsWith('لا تملك')) {
          message = friendly;
        }
      });
      return {};
    } on TimeoutException {
      setState(() {
        isLoading = false;
        message =
            'انتهت المهلة أثناء الاتصال بالخادم. تحقق من الشبكة وحاول مجدداً.';
      });
      return {};
    } catch (e) {
      setState(() {
        isLoading = false;
        message = 'خطأ غير متوقع أثناء جلب السجلات: $e';
      });
      return {};
    }
  }

  Future<void> _showGroupedEventTypesDialog() async {
    // نسخة محلية من الاختيارات للتعديل
    List<String> tempSelectedTypes = List.from(_selectedEventTypes);

    // تجميع الأحداث حسب الفئات
    final Map<String, List<String>> groupedEvents = {
      '🔄 أحداث الاشتراكات': [],
      '💳 أحداث المحفظة': [],
      '💰 أحداث الدفع': [],
      '🎫 أحداث الخصومات': [],
      '🔐 أحداث النظام': [],
    };

    // تصنيف الأحداث
    for (var eventType in _eventTypes) {
      if (eventType.contains('PLAN_') || eventType.contains('Subscription')) {
        groupedEvents['🔄 أحداث الاشتراكات']!.add(eventType);
      } else if (eventType.contains('WALLET_') ||
          eventType.contains('Wallet')) {
        groupedEvents['💳 أحداث المحفظة']!.add(eventType);
      } else if (eventType.contains('PAYMENT')) {
        groupedEvents['💰 أحداث الدفع']!.add(eventType);
      } else if (eventType.contains('DISCOUNT')) {
        groupedEvents['🎫 أحداث الخصومات']!.add(eventType);
      } else {
        groupedEvents['🔐 أحداث النظام']!.add(eventType);
      }
    }

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text(
                'اختر نوع الحدث',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              content: SizedBox(
                width: double.maxFinite,
                height: 500,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: groupedEvents.entries.map((group) {
                      if (group.value.isEmpty) return const SizedBox.shrink();

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // عنوان المجموعة
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: Text(
                              group.key,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo,
                              ),
                            ),
                          ),
                          // أحداث المجموعة
                          ...group.value.map((eventType) {
                            return CheckboxListTile(
                              dense: true,
                              title: Text(
                                translateEventType(eventType),
                                style: const TextStyle(fontSize: 14),
                              ),
                              value: tempSelectedTypes.contains(eventType),
                              onChanged: (bool? value) {
                                setDialogState(() {
                                  if (value == true) {
                                    tempSelectedTypes.add(eventType);
                                  } else {
                                    tempSelectedTypes.remove(eventType);
                                  }
                                });
                              },
                              controlAffinity: ListTileControlAffinity.leading,
                            );
                          }),
                          const Divider(),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    setDialogState(() {
                      tempSelectedTypes.clear();
                    });
                  },
                  child: const Text('مسح الكل'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: const Text('إلغاء'),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _selectedEventTypes = tempSelectedTypes;
                    });
                    Navigator.pop(context);
                  },
                  child: const Text('تطبيق'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _applyFilters() {
    setState(() {
      _currentPage = 1;
      isLoading = true;
      message = hasActiveFilters
          ? "جاري تطبيق التصفية..."
          : "جاري تحميل جميع البيانات...";
    });
    fetchAuditLogs();
    fetchSummary();
  }

  void _resetFilters() {
    setState(() {
      _selectedZone = null;
      _selectedEventTypes.clear();
      _usernameController.clear();
      _fromDateController.clear();
      _toDateController.clear();
      _currentPage = 1;
      isLoading = true;
    });
    fetchAuditLogs();
    fetchSummary();
  }

  // الدالة الجديدة: جلب كل النتائج من جميع الصفحات (وليس الصفحة الحالية فقط)
  Future<List<dynamic>> fetchAllAuditLogs() async {
    List<dynamic> allLogs = [];
    String toDate = _toDateController.text;
    if (toDate.isNotEmpty) {
      toDate = "${toDate.split('T')[0]}T23:59:59";
    }
    int page = 1;
    while (true) {
      // بناء الـ query parameters للتصدير
      Map<String, String> queryParams = {
        'pageSize': _pageSize.toString(),
        'pageNumber': page.toString(),
        'sortCriteria.property': 'CreatedAt',
        'sortCriteria.direction': 'desc',
      };

      if (_selectedZone != null && _selectedZone!.isNotEmpty) {
        queryParams['zoneIds'] = _selectedZone!;
      }
      if (_selectedEventTypes.isNotEmpty) {
        queryParams['eventTypes'] = _selectedEventTypes.join(',');
      }
      if (_usernameController.text.isNotEmpty) {
        queryParams['username'] = _usernameController.text.trim();
      }
      if (_fromDateController.text.isNotEmpty) {
        queryParams['createdAt.from'] = _fromDateController.text;
      }
      if (toDate.isNotEmpty && _toDateController.text.isNotEmpty) {
        queryParams['createdAt.to'] = toDate;
      }

      final url = Uri.https('api.ftth.iq', '/api/audit-logs', queryParams);

      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer ${widget.authToken}',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final items = data['items'] as List;
        allLogs.addAll(items);
        if (items.length < _pageSize) break;
        page++;
      } else {
        break;
      }
    }
    return allLogs;
  }

  // تصدير كل النتائج إلى جداول جوجل
  Future<void> _exportToGoogleSheet() async {
    try {
      setState(() {
        message = "جاري تصدير جميع البيانات إلى جداول جوجل، الرجاء الانتظار...";
      });

      // اجلب كل النتائج (وليس فقط الصفحة الحالية)
      List<dynamic> allLogs = await fetchAllAuditLogs();

      if (allLogs.isEmpty) {
        setState(() {
          message = "لا توجد بيانات لتصديرها.";
        });
        return;
      }

      List<List<dynamic>> rows = [
        [
          'نوع الحدث',
          'المستخدم',
          'العميل',
          'المنطقة',
          'المبلغ',
          'نقدي',
          'ناجح',
          'نوع مالك المحفظة',
          'معرف نوع المالك',
          'التاريخ',
        ]
      ];
      for (var log in allLogs) {
        rows.add([
          translateEventType(log['eventType']?.toString() ?? ''),
          log['actor']?['username']?.toString() ?? '-',
          log['customer']?['displayValue']?.toString() ?? '-',
          log['zone']?['displayValue']?.toString() ?? '-',
          log['amount']?.toString() ?? '-',
          (log['isMonetary'] == true) ? 'نعم' : 'لا',
          (log['isSuccessful'] == true) ? 'نعم' : 'لا',
          log['walletOwnerType']?['entityType']?.toString() ?? '-',
          log['walletOwnerType']?['id']?.toString() ?? '-',
          log['createdAt']?.toString() ?? '-',
        ]);
      }

      final response = await http.post(
        Uri.parse(googleScriptUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(rows),
      );

      if (response.statusCode == 200 || response.statusCode == 302) {
        setState(() {
          message =
              "✅ تم تصدير جميع البيانات بنجاح إلى جداول جوجل. يمكنك فتح الجدول من الزر أدناه.";
        });
      } else {
        setState(() {
          message = "❌ حدث خطأ في التصدير: ${response.body}";
        });
      }
    } catch (e) {
      setState(() {
        message = "❌ حدث خطأ أثناء التصدير: $e";
      });
    }
  }

  // تصدير البيانات إلى ملف Excel
  Future<void> _exportToExcel() async {
    try {
      setState(() {
        message = "جاري تصدير البيانات إلى ملف Excel، الرجاء الانتظار...";
      });

      // اجلب كل النتائج
      List<dynamic> allLogs = await fetchAllAuditLogs();

      if (allLogs.isEmpty) {
        setState(() {
          message = "لا توجد بيانات لتصديرها.";
        });
        return;
      }

      // إنشاء ملف Excel جديد
      var excelFile = excel.Excel.createExcel();
      excel.Sheet sheetObject = excelFile['Sheet1'];

      // إضافة العناوين
      List<String> headers = [
        'نوع الحدث',
        'المستخدم',
        'العميل',
        'المنطقة',
        'المبلغ',
        'نقدي',
        'ناجح',
        'نوع مالك المحفظة',
        'معرف نوع المالك',
        'التاريخ'
      ];

      for (int i = 0; i < headers.length; i++) {
        var cell = sheetObject.cell(
            excel.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        cell.value = excel.TextCellValue(headers[i]);
        // تنسيق العناوين
        cell.cellStyle = excel.CellStyle(
          bold: true,
          backgroundColorHex: excel.ExcelColor.blue,
          fontColorHex: excel.ExcelColor.white,
        );
      }

      // إضافة البيانات
      for (int rowIndex = 0; rowIndex < allLogs.length; rowIndex++) {
        var log = allLogs[rowIndex];

        List<String> rowData = [
          translateEventType(log['eventType']?.toString() ?? ''),
          log['actor']?['username']?.toString() ?? '-',
          log['customer']?['displayValue']?.toString() ?? '-',
          log['zone']?['displayValue']?.toString() ?? '-',
          log['amount']?.toString() ?? '-',
          (log['isMonetary'] == true) ? 'نعم' : 'لا',
          (log['isSuccessful'] == true) ? 'نعم' : 'لا',
          log['walletOwnerType']?['entityType']?.toString() ?? '-',
          log['walletOwnerType']?['id']?.toString() ?? '-',
          log['createdAt']?.toString() ?? '-',
        ];

        for (int colIndex = 0; colIndex < rowData.length; colIndex++) {
          var cell = sheetObject.cell(excel.CellIndex.indexByColumnRow(
              columnIndex: colIndex, rowIndex: rowIndex + 1));
          cell.value = excel.TextCellValue(rowData[colIndex]);
        }
      }

      // حفظ الملف
      var fileBytes = excelFile.save();
      if (fileBytes != null) {
        final directory = await getApplicationDocumentsDirectory();
        final file = File(
            '${directory.path}/audit_logs_${DateTime.now().millisecondsSinceEpoch}.xlsx');
        await file.writeAsBytes(fileBytes);

        setState(() {
          message = "✅ تم تصدير البيانات بنجاح إلى: ${file.path}";
        });
      }
    } catch (e) {
      setState(() {
        message = "❌ حدث خطأ أثناء تصدير Excel: $e";
      });
    }
  }

  // عرض نافذة كلمة المرور للتصدير
  Future<void> _showPasswordDialog(String exportType) async {
    final TextEditingController passwordController = TextEditingController();

    // جلب كلمة المرور من نظام الصلاحيات
    String? storedPassword;
    try {
      storedPassword =
          await PermissionsService.getSecondSystemDefaultPassword();
    } catch (e) {
      print('خطأ في جلب كلمة المرور: $e');
    }

    // إذا لم توجد كلمة مرور محفوظة، استخدم القيمة الافتراضية
    String correctPassword = storedPassword ?? "7777";

    // إذا كانت كلمة المرور فارغة، استخدم القيمة الافتراضية
    if (correctPassword.trim().isEmpty) {
      correctPassword = "7777";
    }

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.lock, color: Colors.indigo),
              SizedBox(width: 8),
              Text(
                'كلمة المرور المطلوبة',
                style: TextStyle(color: Colors.indigo),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'يرجى إدخال كلمة المرور للمتابعة مع التصدير',
                style: TextStyle(fontSize: 14),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 8),
              Text(
                'كلمة المرور موجودة في الصلاحيات > كلمة المرور الافتراضية',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 16),
              TextField(
                controller: passwordController,
                obscureText: true,
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  labelText: 'كلمة المرور',
                  prefixIcon: Icon(Icons.key),
                  border: OutlineInputBorder(),
                  hintText: 'أدخل كلمة المرور',
                ),
                onSubmitted: (value) {
                  if (value == correctPassword) {
                    Navigator.of(context).pop();
                    _executeExport(exportType);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('❌ كلمة المرور غير صحيحة'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('إلغاء', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                if (passwordController.text == correctPassword) {
                  Navigator.of(context).pop();
                  _executeExport(exportType);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('❌ كلمة المرور غير صحيحة'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
              ),
              child: Text('تأكيد'),
            ),
          ],
        );
      },
    );
  }

  // تنفيذ التصدير بعد التحقق من كلمة المرور
  void _executeExport(String exportType) {
    if (exportType == 'google_sheets') {
      _exportToGoogleSheet();
    } else if (exportType == 'excel') {
      _exportToExcel();
    }
  }

  @override
  Widget build(BuildContext context) {
    final formattedTotalAmount =
        NumberFormat("#,###").format(_totalAmount.toInt());

    return Scaffold(
      appBar: AppBar(
        title: Text('تفاصيل البيانات - ${widget.username}'),
        backgroundColor: Colors.indigo,
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: _showRaw ? 'إخفاء الخام' : 'عرض الخام',
            icon: Icon(_showRaw ? Icons.code_off : Icons.code),
            onPressed: () {
              setState(() {
                _showRaw = !_showRaw;
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'إعادة تحميل الصفحة',
            onPressed: () {
              setState(() {
                isLoading = true;
              });
              fetchAuditLogs();
              fetchSummary();
            },
          ),
          IconButton(
            icon: Stack(
              children: [
                Icon(Icons.filter_list, color: Colors.white),
                if (hasActiveFilters)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      constraints: BoxConstraints(
                        minWidth: 14,
                        minHeight: 14,
                      ),
                      child: Text(
                        '●',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) {
                  return AlertDialog(
                    title: Text('تصفية النتائج',
                        style: TextStyle(color: Colors.indigo)),
                    content: SingleChildScrollView(
                      child: Column(
                        children: [
                          DropdownButtonFormField<String>(
                            initialValue: _selectedZone,
                            items: _zones.map((zone) {
                              return DropdownMenuItem(
                                value: zone,
                                child: Text(zone),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setState(() {
                                _selectedZone = value;
                              });
                            },
                            decoration: InputDecoration(
                              labelText: 'المنطقة',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          SizedBox(height: 10),
                          // تصفية نوع الحدث - عرض مجمع
                          InkWell(
                            onTap: _showGroupedEventTypesDialog,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 16),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade400),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _selectedEventTypes.isNotEmpty
                                          ? _selectedEventTypes.length == 1
                                              ? translateEventType(
                                                  _selectedEventTypes.first)
                                              : 'مختار ${_selectedEventTypes.length} أنواع أحداث'
                                          : 'نوع الحدث',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: _selectedEventTypes.isNotEmpty
                                            ? Colors.black87
                                            : Colors.grey[600],
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    Icons.arrow_drop_down,
                                    color: Colors.grey[600],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          SizedBox(height: 10),
                          TextFormField(
                            controller: _usernameController,
                            decoration: InputDecoration(
                              labelText: 'اسم المستخدم',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          SizedBox(height: 10),
                          TextFormField(
                            controller: _fromDateController,
                            decoration: InputDecoration(
                              labelText: 'تاريخ البدء من',
                              border: OutlineInputBorder(),
                            ),
                            onTap: () async {
                              final selectedDate = await showDatePicker(
                                context: context,
                                initialDate: DateTime.now(),
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2100),
                              );
                              if (selectedDate != null) {
                                setState(() {
                                  _fromDateController.text =
                                      selectedDate.toIso8601String();
                                });
                              }
                            },
                          ),
                          SizedBox(height: 10),
                          TextFormField(
                            controller: _toDateController,
                            decoration: InputDecoration(
                              labelText: 'تاريخ البدء إلى',
                              border: OutlineInputBorder(),
                            ),
                            onTap: () async {
                              final selectedDate = await showDatePicker(
                                context: context,
                                initialDate: DateTime.now(),
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2100),
                              );
                              if (selectedDate != null) {
                                setState(() {
                                  _toDateController.text =
                                      selectedDate.toIso8601String();
                                });
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: _resetFilters,
                        child: Text('إلغاء التصفية',
                            style: TextStyle(color: Colors.red)),
                      ),
                      TextButton(
                        onPressed: () {
                          _applyFilters();
                          Navigator.pop(context);
                        },
                        child: Text('تطبيق التصفية',
                            style: TextStyle(color: Colors.indigo)),
                      ),
                    ],
                  );
                },
              );
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.download, color: Colors.white),
            tooltip: 'خيارات التصدير',
            onSelected: (String value) {
              _showPasswordDialog(value);
            },
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem<String>(
                value: 'google_sheets',
                child: ListTile(
                  leading: Icon(Icons.cloud_upload, color: Colors.green),
                  title: Text('تصدير إلى جداول جوجل'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem<String>(
                value: 'excel',
                child: ListTile(
                  leading: Icon(Icons.file_download, color: Colors.blue),
                  title: Text('تصدير إلى Excel'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator(color: Colors.indigo))
          : SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    if (message.isNotEmpty)
                      Column(
                        children: [
                          Container(
                            padding: EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: message.startsWith('✅')
                                  ? Colors.green[50]
                                  : Colors.red[50],
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: SelectableText(
                              message,
                              style: TextStyle(
                                color: message.startsWith('✅')
                                    ? Colors.green[700]
                                    : Colors.red,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                    // إظهار الفلاتر النشطة
                    if (hasActiveFilters)
                      Container(
                        width: double.infinity,
                        margin: EdgeInsets.only(bottom: 20),
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.blue[200]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.filter_list,
                                    color: Colors.blue[700], size: 20),
                                SizedBox(width: 8),
                                Text(
                                  'الفلاتر النشطة:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue[700],
                                  ),
                                ),
                                Spacer(),
                                TextButton(
                                  onPressed: _resetFilters,
                                  child: Text(
                                    'مسح الفلاتر',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                if (_selectedZone != null)
                                  Chip(
                                    label: Text('المنطقة: $_selectedZone'),
                                    backgroundColor: Colors.blue[100],
                                  ),
                                if (_usernameController.text.isNotEmpty)
                                  Chip(
                                    label: Text(
                                        'المستخدم: ${_usernameController.text}'),
                                    backgroundColor: Colors.green[100],
                                  ),
                                if (_selectedEventTypes.isNotEmpty)
                                  Chip(
                                    label: Text(
                                        'الأحداث: ${_selectedEventTypes.length}'),
                                    backgroundColor: Colors.orange[100],
                                  ),
                                if (_fromDateController.text.isNotEmpty)
                                  Chip(
                                    label: Text(
                                        'من: ${_fromDateController.text.split('T')[0]}'),
                                    backgroundColor: Colors.purple[100],
                                  ),
                                if (_toDateController.text.isNotEmpty)
                                  Chip(
                                    label: Text(
                                        'إلى: ${_toDateController.text.split('T')[0]}'),
                                    backgroundColor: Colors.purple[100],
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: _buildInfoCard(
                            title: 'العدد الإجمالي',
                            value: '$_totalCount',
                            color: Colors.blue[50]!,
                          ),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: _buildInfoCard(
                            title: 'المجموع الكلي',
                            value: '$formattedTotalAmount  ',
                            color: Colors.green[50]!,
                          ),
                        ),
                      ],
                    ),
                    // عرض بيانات المحفظة
                    if (_walletDataLoaded) ...[
                      SizedBox(height: 20),
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.indigo[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.indigo[200]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.account_balance_wallet,
                                    color: Colors.indigo, size: 24),
                                SizedBox(width: 8),
                                Text(
                                  'بيانات المحفظة الحالية',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.indigo[800],
                                  ),
                                ),
                                Spacer(),
                                IconButton(
                                  icon:
                                      Icon(Icons.refresh, color: Colors.indigo),
                                  tooltip: 'تحديث بيانات المحفظة',
                                  onPressed: _fetchWalletBalance,
                                ),
                              ],
                            ),
                            SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildWalletInfoTile(
                                    'رصيد المحفظة الرئيسية',
                                    NumberFormat('#,###')
                                        .format(_walletBalance.toInt()),
                                    Icons.account_balance,
                                    Colors.green,
                                  ),
                                ),
                                SizedBox(width: 12),
                                Expanded(
                                  child: _buildWalletInfoTile(
                                    'العمولة',
                                    NumberFormat('#,###')
                                        .format(_commission.toInt()),
                                    Icons.percent,
                                    Colors.orange,
                                  ),
                                ),
                              ],
                            ),
                            if (_hasTeamMemberWallet) ...[
                              SizedBox(height: 12),
                              _buildWalletInfoTile(
                                'محفظة عضو الفريق',
                                NumberFormat('#,###')
                                    .format(_teamMemberWalletBalance.toInt()),
                                Icons.group,
                                Colors.blue,
                              ),
                            ],
                            SizedBox(height: 12),
                            Container(
                              padding: EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey[300]!),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.info_outline,
                                      color: Colors.grey[600], size: 16),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'هذه البيانات محدثة من المصدر ويمكن إعادة تحديثها في أي وقت',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    SizedBox(height: 20),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: NeverScrollableScrollPhysics(),
                      itemCount: _auditLogs.length,
                      itemBuilder: (context, index) {
                        final log = _auditLogs[index] ?? {};
                        final eventType = translateEventType(
                            (log['eventType'] ?? '').toString());
                        final amountNum = (log['amount'] is num)
                            ? (log['amount'] as num)
                            : null;
                        final amountStr = amountNum != null
                            ? NumberFormat('#,###').format(amountNum)
                            : '-';
                        final actorUsername =
                            log['actor']?['username']?.toString() ?? '-';
                        final customerName =
                            log['customer']?['displayValue']?.toString() ?? '-';
                        final zoneName =
                            log['zone']?['displayValue']?.toString() ?? '-';
                        final isMonetary = log['isMonetary'] ?? false;
                        final isSuccessful = log['isSuccessful'] ?? false;
                        final walletOwnerType =
                            log['walletOwnerType']?['entityType']?.toString() ??
                                '-';
                        final walletOwnerTypeId =
                            log['walletOwnerType']?['id']?.toString() ?? '-';
                        DateTime? created;
                        final createdRaw = log['createdAt']?.toString();
                        try {
                          if (createdRaw != null) {
                            created = DateTime.parse(createdRaw).toLocal();
                          }
                        } catch (_) {}
                        final createdFmt = created != null
                            ? DateFormat('yyyy-MM-dd HH:mm').format(created)
                            : (createdRaw ?? '-');

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                          child: InkWell(
                            onTap: () => _showCompleteTransactionDetails(log),
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      CircleAvatar(
                                        backgroundColor: Colors.indigo.shade100,
                                        child: const Icon(Icons.event,
                                            color: Colors.indigo, size: 20),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    eventType,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.indigo,
                                                    ),
                                                  ),
                                                ),
                                                PopupMenuButton<String>(
                                                  icon: Icon(Icons.more_vert,
                                                      size: 18,
                                                      color: Colors.grey[600]),
                                                  tooltip: 'المزيد من التفاصيل',
                                                  onSelected: (String value) {
                                                    switch (value) {
                                                      case 'transaction_details':
                                                        _showTransactionDetails(
                                                            log);
                                                        break;
                                                      case 'customer_wallet':
                                                        _showCustomerWalletInfo(
                                                            log);
                                                        break;
                                                      case 'full_json':
                                                        _showFullJsonDialog(
                                                            log);
                                                        break;
                                                    }
                                                  },
                                                  itemBuilder:
                                                      (BuildContext context) =>
                                                          [
                                                    PopupMenuItem<String>(
                                                      value:
                                                          'transaction_details',
                                                      child: ListTile(
                                                        leading: Icon(
                                                            Icons.info_outline,
                                                            color: Colors.blue),
                                                        title: Text(
                                                            'تفاصيل العملية'),
                                                        contentPadding:
                                                            EdgeInsets.zero,
                                                      ),
                                                    ),
                                                    PopupMenuItem<String>(
                                                      value: 'customer_wallet',
                                                      child: ListTile(
                                                        leading: Icon(
                                                            Icons
                                                                .account_balance_wallet,
                                                            color:
                                                                Colors.green),
                                                        title: Text(
                                                            'محفظة العميل'),
                                                        contentPadding:
                                                            EdgeInsets.zero,
                                                      ),
                                                    ),
                                                    PopupMenuItem<String>(
                                                      value: 'full_json',
                                                      child: ListTile(
                                                        leading: Icon(
                                                            Icons.code,
                                                            color:
                                                                Colors.orange),
                                                        title: Text(
                                                            'البيانات الكاملة'),
                                                        contentPadding:
                                                            EdgeInsets.zero,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            _buildDetailRow(
                                                'المستخدم', actorUsername),
                                            _buildDetailRow(
                                                'العميل', customerName),
                                            _buildDetailRow(
                                                'المنطقة', zoneName),
                                            _buildDetailRow('المبلغ', amountStr,
                                                valueColor: amountNum != null
                                                    ? (amountNum >= 0
                                                        ? Colors.green.shade700
                                                        : Colors.red.shade700)
                                                    : Colors.black87,
                                                isBold: true),
                                            _buildDetailRow('نقدي',
                                                isMonetary ? '✅ نعم' : '❌ لا',
                                                valueColor: isMonetary
                                                    ? Colors.green.shade700
                                                    : Colors.red.shade700),
                                            _buildDetailRow('ناجح',
                                                isSuccessful ? '✅ نعم' : '❌ لا',
                                                valueColor: isSuccessful
                                                    ? Colors.green.shade700
                                                    : Colors.red.shade700),
                                            if (walletOwnerType != '-')
                                              _buildDetailRow('نوع المحفظة',
                                                  walletOwnerType,
                                                  valueColor:
                                                      Colors.blue.shade700),
                                            if (walletOwnerTypeId != '-')
                                              _buildDetailRow(
                                                  'معرف ', walletOwnerTypeId,
                                                  valueColor:
                                                      Colors.blue.shade600,
                                                  small: true),
                                            _buildDetailRow(
                                                'التاريخ', createdFmt,
                                                small: true),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (_showRaw) _buildRawJsonBlock(log),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withValues(alpha: 0.3),
              spreadRadius: 1,
              blurRadius: 5,
              offset: Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: _currentPage > 1
                    ? () {
                        setState(() {
                          _currentPage--;
                          isLoading = true;
                          fetchAuditLogs();
                        });
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                ),
                child: Text('السابق'),
              ),
              SizedBox(width: 16),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.indigo.shade200),
                ),
                child: Text(
                  '$_currentPage / $_totalPages',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo.shade700,
                  ),
                ),
              ),
              SizedBox(width: 16),
              ElevatedButton(
                onPressed: _currentPage < _totalPages
                    ? () {
                        setState(() {
                          _currentPage++;
                          isLoading = true;
                          fetchAuditLogs();
                        });
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                ),
                child: Text('التالي'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard(
      {required String title, required String value, required Color color}) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      color: color,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.indigo,
              ),
            ),
            SizedBox(height: 10),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRawJsonBlock(dynamic log) {
    String pretty;
    try {
      pretty = const JsonEncoder.withIndent('  ').convert(log);
    } catch (_) {
      pretty = log.toString();
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SelectableText(
          pretty,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value,
      {Color? valueColor, bool isBold = false, bool small = false}) {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: small ? 11 : 12,
                fontWeight: FontWeight.w600,
                color: Colors.indigo.shade700,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                fontSize: small ? 11 : 12,
                fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
                color: valueColor ?? Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWalletInfoTile(
      String title, String value, IconData icon, Color color) {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // عرض تفاصيل العملية
  void _showTransactionDetails(Map<String, dynamic> transaction) async {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.height * 0.8,
          padding: EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue),
                  SizedBox(width: 8),
                  Text(
                    'تفاصيل العملية',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  Spacer(),
                  IconButton(
                    icon: Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              Divider(),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDetailSection('معلومات أساسية', {
                        'معرف العملية': transaction['id']?.toString() ?? '-',
                        'نوع الحدث': translateEventType(
                            transaction['eventType']?.toString() ?? ''),
                        'المبلغ':
                            '${transaction['amount']?.toString() ?? '0'} دينار',
                        'حالة العملية': transaction['isSuccessful'] == true
                            ? 'ناجحة ✅'
                            : 'فاشلة ❌',
                        'نوع مالي': transaction['isMonetary'] == true
                            ? 'نعم ✅'
                            : 'لا ❌',
                        'التاريخ': _formatDateTime(
                            transaction['createdAt']?.toString()),
                      }),
                      SizedBox(height: 16),
                      _buildDetailSection('معلومات المستخدم', {
                        'اسم المستخدم':
                            transaction['actor']?['username']?.toString() ??
                                '-',
                        'نوع الحساب': transaction['actor']?['accountType']
                                    ?['displayValue']
                                ?.toString() ??
                            '-',
                        'معرف المستخدم':
                            transaction['actor']?['id']?.toString() ?? '-',
                      }),
                      SizedBox(height: 16),
                      if (transaction['customer'] != null)
                        _buildDetailSection('معلومات العميل', {
                          'اسم العميل': transaction['customer']?['displayValue']
                                  ?.toString() ??
                              '-',
                          'معرف العميل':
                              transaction['customer']?['id']?.toString() ?? '-',
                        }),
                      SizedBox(height: 16),
                      _buildDetailSection('معلومات المحفظة', {
                        'نوع مالك المحفظة': transaction['walletOwnerType']
                                    ?['entityType']
                                ?.toString() ??
                            '-',
                        'وصف المحفظة': transaction['walletOwnerType']
                                    ?['displayValue']
                                ?.toString() ??
                            '-',
                        'معرف المحفظة':
                            transaction['walletOwnerType']?['id']?.toString() ??
                                '-',
                      }),
                      SizedBox(height: 16),
                      if (transaction['zone'] != null)
                        _buildDetailSection('معلومات المنطقة', {
                          'اسم المنطقة': transaction['zone']?['displayValue']
                                  ?.toString() ??
                              '-',
                          'معرف المنطقة':
                              transaction['zone']?['id']?.toString() ?? '-',
                        }),
                      SizedBox(height: 16),
                      if (transaction['subscription'] != null)
                        _buildDetailSection('معلومات الاشتراك', {
                          'نوع الاشتراك': transaction['subscription']
                                      ?['displayValue']
                                  ?.toString() ??
                              '-',
                          'معرف الاشتراك':
                              transaction['subscription']?['id']?.toString() ??
                                  '-',
                        }),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // عرض معلومات محفظة العميل
  void _showCustomerWalletInfo(Map<String, dynamic> transaction) async {
    final customerId = transaction['customer']?['id']?.toString();
    if (customerId == null || customerId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('لا يمكن العثور على معرف العميل')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.height * 0.6,
          padding: EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(Icons.account_balance_wallet, color: Colors.green),
                  SizedBox(width: 8),
                  Text(
                    'محفظة العميل',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  Spacer(),
                  IconButton(
                    icon: Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              Divider(),
              Expanded(
                child: FutureBuilder<Map<String, dynamic>?>(
                  future: _fetchCustomerWalletBalance(customerId),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Center(child: CircularProgressIndicator());
                    }

                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          'خطأ في جلب البيانات: ${snapshot.error}',
                          style: TextStyle(color: Colors.red),
                        ),
                      );
                    }

                    if (!snapshot.hasData) {
                      return Center(child: Text('لا توجد بيانات للمحفظة'));
                    }

                    final walletData = snapshot.data!['model'] ?? {};
                    return SingleChildScrollView(
                      child: Column(
                        children: [
                          _buildDetailSection('رصيد المحفظة', {
                            'الرصيد الحالي':
                                '${walletData['balance']?.toString() ?? '0'} دينار',
                            'تاريخ التحديث': _formatDateTime(
                                walletData['lastUpdated']?.toString()),
                          }),
                          SizedBox(height: 16),
                          _buildDetailSection('معلومات العميل', {
                            'اسم العميل': transaction['customer']
                                        ?['displayValue']
                                    ?.toString() ??
                                '-',
                            'معرف العميل': customerId,
                          }),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // عرض JSON كامل
  void _showFullJsonDialog(Map<String, dynamic> transaction) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.95,
          height: MediaQuery.of(context).size.height * 0.8,
          padding: EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(Icons.code, color: Colors.orange),
                  SizedBox(width: 8),
                  Text(
                    'البيانات الكاملة (JSON)',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                    ),
                  ),
                  Spacer(),
                  IconButton(
                    icon: Icon(Icons.copy),
                    tooltip: 'نسخ JSON',
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(
                          text: const JsonEncoder.withIndent('  ')
                              .convert(transaction),
                        ),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('تم نسخ البيانات')),
                      );
                    },
                  ),
                  IconButton(
                    icon: Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              Divider(),
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
                      const JsonEncoder.withIndent('  ').convert(transaction),
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // بناء قسم تفاصيل
  Widget _buildDetailSection(String title, Map<String, String> details) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.indigo,
            ),
          ),
          SizedBox(height: 8),
          ...details.entries.map((entry) => Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 100,
                      child: Text(
                        '${entry.key}:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700],
                        ),
                      ),
                    ),
                    Expanded(
                      child: SelectableText(
                        entry.value,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  // تنسيق التاريخ والوقت
  String _formatDateTime(String? dateTimeString) {
    if (dateTimeString == null || dateTimeString.isEmpty) return '-';

    try {
      final dateTime = DateTime.parse(dateTimeString);
      return DateFormat('yyyy-MM-dd HH:mm:ss').format(dateTime.toLocal());
    } catch (e) {
      return dateTimeString;
    }
  }

  // عرض جميع تفاصيل العملية الشاملة
  void _showCompleteTransactionDetails(Map<String, dynamic> transaction) async {
    final customerId = transaction['customer']?['id']?.toString();

    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: SizedBox(
          width: MediaQuery.of(context).size.width * 0.95,
          height: MediaQuery.of(context).size.height * 0.9,
          child: DefaultTabController(
            length: customerId != null ? 4 : 3,
            child: Column(
              children: [
                // Header
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.indigo[50],
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(8),
                      topRight: Radius.circular(8),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.receipt_long, color: Colors.indigo, size: 28),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'تفاصيل العملية الشاملة',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo[800],
                              ),
                            ),
                            Text(
                              translateEventType(
                                  transaction['eventType']?.toString() ?? ''),
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.indigo[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: Colors.indigo),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                // Tabs
                Container(
                  color: Colors.indigo[50],
                  child: TabBar(
                    labelColor: Colors.indigo[800],
                    unselectedLabelColor: Colors.indigo[400],
                    indicatorColor: Colors.indigo,
                    tabs: [
                      Tab(icon: Icon(Icons.info), text: 'التفاصيل'),
                      Tab(
                          icon: Icon(Icons.account_balance_wallet),
                          text: 'محفظتي'),
                      if (customerId != null)
                        Tab(icon: Icon(Icons.person), text: 'محفظة العميل'),
                      Tab(icon: Icon(Icons.code), text: 'البيانات الخام'),
                    ],
                  ),
                ),
                // Tab Content
                Expanded(
                  child: TabBarView(
                    children: [
                      // Tab 1: التفاصيل
                      _buildTransactionDetailsTab(transaction),
                      // Tab 2: محفظتي
                      _buildMyWalletTab(transaction),
                      // Tab 3: محفظة العميل (إذا كان هناك عميل)
                      if (customerId != null)
                        _buildCustomerWalletTab(customerId),
                      // Tab 4: البيانات الخام
                      _buildRawDataTab(transaction),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // بناء تاب التفاصيل
  Widget _buildTransactionDetailsTab(Map<String, dynamic> transaction) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDetailSection('معلومات أساسية', {
            'معرف العملية': transaction['id']?.toString() ?? '-',
            'نوع الحدث':
                translateEventType(transaction['eventType']?.toString() ?? ''),
            'المبلغ': '${transaction['amount']?.toString() ?? '0'} دينار',
            'حالة العملية':
                transaction['isSuccessful'] == true ? 'ناجحة ✅' : 'فاشلة ❌',
            'نوع مالي': transaction['isMonetary'] == true ? 'نعم ✅' : 'لا ❌',
            'التاريخ': _formatDateTime(transaction['createdAt']?.toString()),
          }),
          SizedBox(height: 16),
          _buildDetailSection('معلومات المستخدم', {
            'اسم المستخدم':
                transaction['actor']?['username']?.toString() ?? '-',
            'نوع الحساب': transaction['actor']?['accountType']?['displayValue']
                    ?.toString() ??
                '-',
            'معرف المستخدم': transaction['actor']?['id']?.toString() ?? '-',
          }),
          SizedBox(height: 16),
          if (transaction['customer'] != null) ...[
            _buildDetailSection('معلومات العميل', {
              'اسم العميل':
                  transaction['customer']?['displayValue']?.toString() ?? '-',
              'معرف العميل': transaction['customer']?['id']?.toString() ?? '-',
            }),
            SizedBox(height: 16),
          ],
          _buildDetailSection('معلومات المحفظة', {
            'نوع مالك المحفظة':
                transaction['walletOwnerType']?['entityType']?.toString() ??
                    '-',
            'وصف المحفظة':
                transaction['walletOwnerType']?['displayValue']?.toString() ??
                    '-',
            'معرف المحفظة':
                transaction['walletOwnerType']?['id']?.toString() ?? '-',
          }),
          SizedBox(height: 16),
          if (transaction['zone'] != null) ...[
            _buildDetailSection('معلومات المنطقة', {
              'اسم المنطقة':
                  transaction['zone']?['displayValue']?.toString() ?? '-',
              'معرف المنطقة': transaction['zone']?['id']?.toString() ?? '-',
            }),
            SizedBox(height: 16),
          ],
          if (transaction['subscription'] != null) ...[
            _buildDetailSection('معلومات الاشتراك', {
              'نوع الاشتراك':
                  transaction['subscription']?['displayValue']?.toString() ??
                      '-',
              'معرف الاشتراك':
                  transaction['subscription']?['id']?.toString() ?? '-',
            }),
            SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  // بناء تاب محفظتي - عرض الرصيد قبل وبعد العملية
  Widget _buildMyWalletTab(Map<String, dynamic> transaction) {
    // حساب الرصيد قبل وبعد العملية
    final transactionAmount = (transaction['amount'] ?? 0.0).toDouble();

    // محاولة جلب بيانات الرصيد من العملية نفسها إن كانت متوفرة
    final previousBalance = transaction['walletBalanceBefore']?.toDouble() ??
        transaction['previousBalance']?.toDouble();
    final newBalance = transaction['walletBalanceAfter']?.toDouble() ??
        transaction['newBalance']?.toDouble();

    // إذا لم تكن متوفرة في العملية، احسبها من الرصيد الحالي
    final currentBalance = _walletDataLoaded ? _walletBalance : 0.0;
    final balanceBeforeTransaction =
        previousBalance ?? (currentBalance - transactionAmount);
    final balanceAfterTransaction = newBalance ?? currentBalance;

    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          // معلومات العملية
          _buildDetailSection('تأثير العملية على المحفظة', {
            'نوع العملية':
                translateEventType(transaction['eventType']?.toString() ?? ''),
            'مبلغ العملية':
                '${NumberFormat('#,###').format(transactionAmount.abs().toInt())} دينار',
            'اتجاه العملية': transactionAmount >= 0 ? 'إيداع ⬆️' : 'سحب ⬇️',
            'تاريخ العملية':
                _formatDateTime(transaction['createdAt']?.toString()),
            'مصدر البيانات': (previousBalance != null && newBalance != null)
                ? 'من بيانات العملية (دقيق) ✅'
                : 'محسوب من الرصيد الحالي (تقديري) ⚠️',
          }),
          SizedBox(height: 16),

          // الرصيد قبل العملية
          _buildDetailSection('💰 الرصيد قبل العملية', {
            'رصيد المحفظة':
                '${NumberFormat('#,###').format(balanceBeforeTransaction.toInt())} دينار',
            if (_walletDataLoaded && _commission > 0)
              'العمولة':
                  '${NumberFormat('#,###').format(_commission.toInt())} دينار',
            if (_walletDataLoaded && _commission > 0)
              'إجمالي الرصيد':
                  '${NumberFormat('#,###').format((balanceBeforeTransaction + _commission).toInt())} دينار',
          }),
          SizedBox(height: 16),

          // تأثير العملية
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: transactionAmount >= 0 ? Colors.green[50] : Colors.red[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: transactionAmount >= 0
                    ? Colors.green[300]!
                    : Colors.red[300]!,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  transactionAmount >= 0
                      ? Icons.add_circle
                      : Icons.remove_circle,
                  color: transactionAmount >= 0
                      ? Colors.green[700]
                      : Colors.red[700],
                  size: 28,
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        transactionAmount >= 0
                            ? '➕ تم إضافة المبلغ'
                            : '➖ تم خصم المبلغ',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: transactionAmount >= 0
                              ? Colors.green[800]
                              : Colors.red[800],
                        ),
                      ),
                      Text(
                        '${NumberFormat('#,###').format(transactionAmount.abs().toInt())} دينار',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: transactionAmount >= 0
                              ? Colors.green[700]
                              : Colors.red[700],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 16),

          // الرصيد بعد العملية
          _buildDetailSection('💰 الرصيد بعد العملية', {
            'رصيد المحفظة':
                '${NumberFormat('#,###').format(balanceAfterTransaction.toInt())} دينار',
            if (_walletDataLoaded && _commission > 0)
              'العمولة':
                  '${NumberFormat('#,###').format(_commission.toInt())} دينار',
            if (_walletDataLoaded && _commission > 0)
              'إجمالي الرصيد':
                  '${NumberFormat('#,###').format((balanceAfterTransaction + _commission).toInt())} دينار',
          }),

          if (_hasTeamMemberWallet) ...[
            SizedBox(height: 16),
            _buildDetailSection('محفظة عضو الفريق', {
              'رصيد محفظة عضو الفريق':
                  '${NumberFormat('#,###').format(_teamMemberWalletBalance.toInt())} دينار',
              'حالة المحفظة': _hasTeamMemberWallet ? 'نشطة ✅' : 'غير نشطة ❌',
            }),
          ],

          SizedBox(height: 16),

          // ملاحظة هامة
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange[300]!),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orange[700], size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    (previousBalance != null && newBalance != null)
                        ? 'هذه الأرصدة مأخوذة من بيانات العملية الفعلية وقت التنفيذ.'
                        : 'هذه الأرصدة محسوبة بناءً على الرصيد الحالي ومبلغ العملية. قد تختلف عن الأرصدة الفعلية وقت تنفيذ العملية.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange[700],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // بناء تاب محفظة العميل
  Widget _buildCustomerWalletTab(String customerId) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: FutureBuilder<Map<String, dynamic>?>(
        future: _fetchCustomerWalletBalance(customerId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('جاري جلب بيانات محفظة العميل...'),
                ],
              ),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, color: Colors.red, size: 48),
                  SizedBox(height: 16),
                  Text(
                    'خطأ في جلب البيانات',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    snapshot.error.toString(),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.red[700]),
                  ),
                ],
              ),
            );
          }

          if (!snapshot.hasData) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.info_outline, color: Colors.grey, size: 48),
                  SizedBox(height: 16),
                  Text('لا توجد بيانات للمحفظة'),
                ],
              ),
            );
          }

          final walletData = snapshot.data!['model'] ?? {};
          return Column(
            children: [
              _buildDetailSection('رصيد محفظة العميل', {
                'الرصيد الحالي':
                    '${NumberFormat('#,###').format((walletData['balance'] ?? 0).toInt())} دينار',
                'تاريخ آخر تحديث':
                    _formatDateTime(walletData['lastUpdated']?.toString()),
                'معرف العميل': customerId,
              }),
            ],
          );
        },
      ),
    );
  }

  // بناء تاب البيانات الخام
  Widget _buildRawDataTab(Map<String, dynamic> transaction) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              Text(
                'البيانات الخام (JSON)',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange[800],
                ),
              ),
              Spacer(),
              ElevatedButton.icon(
                onPressed: () {
                  Clipboard.setData(
                    ClipboardData(
                      text: const JsonEncoder.withIndent('  ')
                          .convert(transaction),
                    ),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('تم نسخ البيانات إلى الحافظة')),
                  );
                },
                icon: Icon(Icons.copy, size: 16),
                label: Text('نسخ'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: SelectableText(
                const JsonEncoder.withIndent('  ').convert(transaction),
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
