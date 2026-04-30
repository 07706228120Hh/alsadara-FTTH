/// خدمة حفظ سجلات الاشتراكات في VPS
/// خدمة سجلات الاشتراكات عبر VPS API
library;

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_service.dart';

class SubscriptionLogsService {
  static SubscriptionLogsService? _instance;
  static SubscriptionLogsService get instance =>
      _instance ??= SubscriptionLogsService._internal();
  SubscriptionLogsService._internal();

  final ApiService _api = ApiService.instance;

  static const String baseUrl = 'https://api.ramzalsadara.tech/api/internal';

  // API Key للوصول الداخلي
  static const String apiKey = 'sadara-internal-2024-secure-key';

  /// حفظ سجل اشتراك جديد — يرجع ID السجل عند النجاح، أو null عند الفشل
  Future<int?> saveSubscriptionLog({
    // معلومات العميل
    String? customerId,
    String? customerName,
    String? phoneNumber,
    // معلومات الاشتراك
    String? subscriptionId,
    String? planName,
    double? planPrice,
    int? commitmentPeriod,
    String? bundleId,
    String? currentStatus,
    String? deviceUsername,
    // معلومات العملية
    String? operationType,
    String? activatedBy,
    DateTime? activationDate,
    String? activationTime,
    String? sessionId,
    // معلومات الموقع
    String? zoneId,
    String? zoneName,
    String? fbgInfo,
    String? fatInfo,
    String? fdtInfo,
    // معلومات المحفظة
    double? walletBalanceBefore,
    double? walletBalanceAfter,
    double? partnerWalletBalanceBefore,
    double? customerWalletBalanceBefore,
    String? currency,
    String? paymentMethod,
    // معلومات الشريك/الموظف
    String? partnerName,
    String? partnerId,
    String? userId,
    String? companyId,
    // حالة العملية
    bool isPrinted = false,
    bool isWhatsAppSent = false,
    String? subscriptionNotes,
    // معلومات إضافية
    String? startDate,
    String? endDate,
    String? apiResponse,
    // حقول تكامل المحاسبة
    String? collectionType,
    String? linkedAgentId,
    String? linkedTechnicianId,
    String? technicianName,
    // حقول الخصم والتسعير
    double? manualDiscount,
    double? systemDiscount,
    bool? systemDiscountEnabled,
    double? basePrice,
    // أجور الصيانة
    double? maintenanceFee,
  }) async {
    try {
      final body = {
        // معلومات العميل
        'customerId': customerId,
        'customerName': customerName,
        'phoneNumber': phoneNumber,
        // معلومات الاشتراك
        'subscriptionId': subscriptionId,
        'planName': planName,
        'planPrice': planPrice,
        'commitmentPeriod': commitmentPeriod,
        'bundleId': bundleId,
        'currentStatus': currentStatus,
        'deviceUsername': deviceUsername,
        // معلومات العملية
        'operationType': operationType,
        'activatedBy': activatedBy,
        'activationDate': activationDate?.toUtc().toIso8601String(),
        'activationTime': activationTime,
        'sessionId': sessionId,
        // معلومات الموقع
        'zoneId': zoneId,
        'zoneName': zoneName,
        'fbgInfo': fbgInfo,
        'fatInfo': fatInfo,
        'fdtInfo': fdtInfo,
        // معلومات المحفظة
        'walletBalanceBefore': walletBalanceBefore,
        'walletBalanceAfter': walletBalanceAfter,
        'partnerWalletBalanceBefore': partnerWalletBalanceBefore,
        'customerWalletBalanceBefore': customerWalletBalanceBefore,
        'currency': currency,
        'paymentMethod': paymentMethod,
        // معلومات الشريك/الموظف
        'partnerName': partnerName,
        'partnerId': partnerId,
        'userId': userId,
        'companyId': companyId,
        // حالة العملية
        'isPrinted': isPrinted,
        'isWhatsAppSent': isWhatsAppSent,
        'subscriptionNotes': subscriptionNotes,
        // معلومات إضافية
        'startDate': startDate,
        'endDate': endDate,
        'apiResponse': apiResponse,
        // حقول تكامل المحاسبة
        'collectionType': collectionType,
        'linkedAgentId': linkedAgentId,
        'linkedTechnicianId': linkedTechnicianId,
        'technicianName': technicianName,
        // حقول الخصم والتسعير
        'manualDiscount': manualDiscount,
        'systemDiscount': systemDiscount,
        'systemDiscountEnabled': systemDiscountEnabled,
        'basePrice': basePrice,
        // أجور الصيانة
        'maintenanceFee': maintenanceFee,
      };

      // إزالة القيم null
      body.removeWhere((key, value) => value == null);

      final response = await http.post(
        Uri.parse('$baseUrl/subscriptionlogs'),
        headers: {
          'Content-Type': 'application/json',
          'X-Api-Key': apiKey,
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        debugPrint('✅ SubscriptionLogsService: تم حفظ السجل بنجاح');
        debugPrint('📦 Response body: ${response.body}');
        // استخراج ID السجل من الاستجابة
        try {
          final responseData = jsonDecode(response.body);
          // الخادم يستخدم PascalCase: "Id" وليس "id"
          final logId =
              responseData['data']?['Id'] ?? responseData['data']?['id'];
          if (logId != null) {
            debugPrint('🆔 SubscriptionLogsService: logId = $logId');
            return logId is int ? logId : int.tryParse(logId.toString());
          }
        } catch (e) {
          debugPrint('⚠️ SubscriptionLogsService: فشل تحليل الاستجابة - $e');
        }
        return -1; // نجح لكن لم نحصل على ID
      } else {
        debugPrint(
            '❌ SubscriptionLogsService: فشل الحفظ - ${response.statusCode}: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('❌ SubscriptionLogsService: خطأ في الحفظ - $e');
      return null;
    }
  }

  /// تحديث حالة السجل (طباعة/واتساب/ملاحظات) بواسطة ID
  Future<bool> updateLogStatus({
    required int logId,
    bool? isPrinted,
    bool? isWhatsAppSent,
    String? notes,
    int? printCount,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (isPrinted != null) body['isPrinted'] = isPrinted;
      if (isWhatsAppSent != null) body['isWhatsAppSent'] = isWhatsAppSent;
      if (notes != null) body['subscriptionNotes'] = notes;
      if (printCount != null) body['printCount'] = printCount;

      final response = await http.put(
        Uri.parse('$baseUrl/subscriptionlogs/$logId'),
        headers: {
          'Content-Type': 'application/json',
          'X-Api-Key': apiKey,
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        debugPrint('✅ SubscriptionLogsService: تم تحديث السجل $logId بنجاح');
        return true;
      } else {
        debugPrint(
            '❌ SubscriptionLogsService: فشل تحديث السجل $logId - ${response.statusCode}');
        return false;
      }
    } catch (e) {
      debugPrint('❌ SubscriptionLogsService: خطأ في التحديث - $e');
      return false;
    }
  }

  /// البحث عن سجل بواسطة SessionId — يرجع الـ ID أو null
  Future<int?> findLogBySessionId(String sessionId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/subscriptionlogs/by-session/$sessionId'),
        headers: {'X-Api-Key': apiKey},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // الخادم يستخدم PascalCase: "Id" وليس "id"
        final id = data['Id'] ?? data['id'];
        return id is int ? id : int.tryParse(id.toString());
      }
      return null;
    } catch (e) {
      debugPrint('❌ SubscriptionLogsService: خطأ في البحث بـ sessionId - $e');
      return null;
    }
  }

  // ═══════ واجهة الاتصالات ═══════

  /// جلب سجلات التوصيلات مجمعة حسب الفني
  Future<Map<String, List<Map<String, dynamic>>>> getConnections({
    DateTime? fromDate,
    DateTime? toDate,
    String? technicianName,
    String? zoneId,
    String? operationType,
    int pageSize = 500,
  }) async {
    try {
      String query = '/subscriptionlogs/connections?pageSize=$pageSize';
      if (fromDate != null) query += '&fromDate=${fromDate.toIso8601String()}';
      if (toDate != null) query += '&toDate=${toDate.toIso8601String()}';
      if (technicianName != null && technicianName.isNotEmpty) {
        query += '&technicianName=${Uri.encodeComponent(technicianName)}';
      }
      if (zoneId != null && zoneId.isNotEmpty) {
        query += '&zoneId=${Uri.encodeComponent(zoneId)}';
      }
      if (operationType != null && operationType.isNotEmpty) {
        query += '&operationType=${Uri.encodeComponent(operationType)}';
      }

      final response = await _api.get(query);
      final Map<String, dynamic> data = response['data'] ?? {};

      // تحويل البيانات إلى التنسيق المطلوب
      final Map<String, List<Map<String, dynamic>>> result = {};
      data.forEach((key, value) {
        if (value is List) {
          result[key] = value.map<Map<String, dynamic>>((item) {
            return {
              'id': item['Id']?.toString() ?? '',
              'customerId': item['CustomerId'] ?? '',
              'customerName': item['CustomerName'] ?? '',
              'phoneNumber': item['PhoneNumber'] ?? '',
              'subscriptionId': item['SubscriptionId'] ?? '',
              'planName': item['PlanName'] ?? '',
              'planPrice': item['PlanPrice']?.toString() ?? '',
              'operationType': item['OperationType'] ?? '',
              'activatedBy': item['ActivatedBy'] ?? '',
              'activationDate': item['ActivationDate'] ?? '',
              'zoneId': item['ZoneId'] ?? '',
              'currentStatus': item['CurrentStatus'] ?? '',
              'currency': item['Currency'] ?? '',
              'paymentMethod': item['PaymentMethod'] ?? '',
              'deviceModel': item['TechnicianName'] ?? '',
              'paymentStatus': item['PaymentStatus'] ?? '',
              'enteredBy': item['ActivatedBy'] ?? '',
            };
          }).toList();
        }
      });

      return result;
    } catch (e) {
      debugPrint('❌ SubscriptionLogsService: خطأ في جلب التوصيلات - $e');
      rethrow;
    }
  }

  /// تحديث حالة الدفع لسجل معين
  Future<void> updatePaymentStatus({
    required String logId,
    required String paymentStatus,
  }) async {
    try {
      await _api.patch(
        '/subscriptionlogs/$logId/payment-status',
        body: {'PaymentStatus': paymentStatus},
      );
      debugPrint('✅ تم تحديث حالة الدفع للسجل $logId');
    } catch (e) {
      debugPrint('❌ خطأ في تحديث حالة الدفع');
      rethrow;
    }
  }

  /// تحديث حالة الدفع لمجموعة سجلات
  Future<void> bulkUpdatePaymentStatus({
    required List<String> ids,
    required String paymentStatus,
  }) async {
    try {
      final longIds =
          ids.map((id) => int.tryParse(id) ?? 0).where((id) => id > 0).toList();
      await _api.patch(
        '/subscriptionlogs/bulk-payment-status',
        body: {
          'Ids': longIds,
          'PaymentStatus': paymentStatus,
        },
      );
      debugPrint('✅ تم تحديث حالة الدفع لـ ${longIds.length} سجل');
    } catch (e) {
      debugPrint('❌ خطأ في تحديث حالة الدفع الجماعي');
      rethrow;
    }
  }

  /// جلب جميع السجلات بمفاتيح عربية
  Future<List<Map<String, dynamic>>> getAllRecords(
      {int pageSize = 1000}) async {
    try {
      final response = await _api.get('/subscriptionlogs?pageSize=$pageSize');
      final List<dynamic> items = response['data'] ?? [];

      return items.map<Map<String, dynamic>>((item) {
        return _mapToArabicKeys(item as Map<String, dynamic>);
      }).toList();
    } catch (e) {
      debugPrint('❌ خطأ في جلب جميع السجلات');
      rethrow;
    }
  }

  /// تحويل مفاتيح API إلى مفاتيح عربية متوافقة مع الواجهة
  Map<String, dynamic> _mapToArabicKeys(Map<String, dynamic> item) {
    return {
      'id': item['Id']?.toString() ?? '',
      'معرف العميل': item['CustomerId'] ?? '',
      'اسم العميل': item['CustomerName'] ?? '',
      'رقم الهاتف': item['PhoneNumber'] ?? '',
      'معرف الاشتراك': item['SubscriptionId'] ?? '',
      'اسم الباقة': item['PlanName'] ?? '',
      'سعر الباقة': item['PlanPrice']?.toString() ?? '',
      'فترة الالتزام': item['CommitmentPeriod']?.toString() ?? '',
      'نوع العملية': item['OperationType'] ?? '',
      'المُفعِّل': item['ActivatedBy'] ?? '',
      'منفذ العملية': item['ActivatedBy'] ?? '',
      'تاريخ التفعيل': item['ActivationDate'] ?? '',
      'التاريخ': item['ActivationDate'] ?? '',
      'الوقت': item['ActivationTime'] ?? '',
      'المنطقة': item['ZoneId'] ?? '',
      'اسم المنطقة': item['ZoneName'] ?? '',
      'الحالة الحالية': item['CurrentStatus'] ?? '',
      'اسم المستخدم للجهاز': item['DeviceUsername'] ?? '',
      'العملة': item['Currency'] ?? '',
      'طريقة الدفع': item['PaymentMethod'] ?? '',
      'FBG': item['FbgInfo'] ?? '',
      'FAT': item['FatInfo'] ?? '',
      'FDT': item['FdtInfo'] ?? '',
      'رصيد المحفظة قبل العملية': item['WalletBalanceBefore']?.toString() ?? '',
      'رصيد المحفظة بعد العملية': item['WalletBalanceAfter']?.toString() ?? '',
      'رصيد محفظة الشريك قبل العملية':
          item['PartnerWalletBalanceBefore']?.toString() ?? '',
      'رصيد محفظة العميل قبل العملية':
          item['CustomerWalletBalanceBefore']?.toString() ?? '',
      'اسم الشريك': item['PartnerName'] ?? '',
      'معرف الشريك': item['PartnerId'] ?? '',
      'تم الطباعة': item['IsPrinted']?.toString() ?? '',
      'ملاحظات الاشتراك': item['SubscriptionNotes'] ?? '',
      'موديل الجهاز': item['TechnicianName'] ?? '',
      'حالة الدفع': item['PaymentStatus'] ?? '',
    };
  }
}
