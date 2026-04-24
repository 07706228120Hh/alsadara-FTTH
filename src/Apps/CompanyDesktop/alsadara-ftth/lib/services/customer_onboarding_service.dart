import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

/// خدمة تسجيل مشترك جديد — Customer Onboarding
/// مبنية من API traffic حقيقي لموقع admin.ftth.iq
class CustomerOnboardingService {
  static const String _baseUrl = 'https://admin.ftth.iq/api';

  static CustomerOnboardingService? _instance;
  static CustomerOnboardingService get instance =>
      _instance ??= CustomerOnboardingService._();
  CustomerOnboardingService._();

  final _auth = AuthService.instance;

  Map<String, String> get _extraHeaders => {
        'Accept': 'application/json, text/plain, */*',
        'X-Client-App': '53d57a7f-3f89-4e9d-873b-3d071bc6dd9f',
        'X-User-Role': '0',
      };

  /// تطبيع العناصر — {self: {id, displayValue}} → {id, displayValue}
  List<Map<String, dynamic>> _normalize(List items) {
    return items.map((item) {
      final m = Map<String, dynamic>.from(item as Map);
      if (m['id'] == null && m['self'] is Map) {
        m['id'] = (m['self'] as Map)['id'];
        m['displayValue'] ??= (m['self'] as Map)['displayValue'];
      }
      return m;
    }).toList();
  }

  /// جلب + تطبيع عام
  Future<List<Map<String, dynamic>>> _fetchList(String url) async {
    final resp = await _auth.authenticatedRequest('GET', url, headers: _extraHeaders);
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      List items;
      if (data is List) {
        items = data;
      } else if (data is Map) {
        final raw = data['items'] ?? data['model'];
        items = (raw is List) ? raw : [];
      } else {
        items = [];
      }
      debugPrint('📦 $url → ${items.length} items');
      return _normalize(items);
    }
    debugPrint('⚠️ $url → status ${resp.statusCode}');
    return [];
  }

  // ═══════════════════════════════════════════
  //  Lookups
  // ═══════════════════════════════════════════

  Future<List<Map<String, dynamic>>> getZones() =>
      _fetchList('$_baseUrl/locations/zones');

  Future<List<Map<String, dynamic>>> getInstallationOptions() =>
      _fetchList('$_baseUrl/requests/customer-onboarding/installation-options');

  Future<List<Map<String, dynamic>>> getPlans() =>
      _fetchList('$_baseUrl/plans');

  Future<String?> getContract() async {
    final resp = await _auth.authenticatedRequest('GET', '$_baseUrl/contracts', headers: _extraHeaders);
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      final model = data['model'] ?? data;
      return model['description']?.toString();
    }
    return null;
  }

  // ═══════════════════════════════════════════
  //  رفع ملف (صور الهوية + التوقيع)
  // ═══════════════════════════════════════════
  /// يرفع ملف فارغ placeholder ويرجع UUID
  /// الموقع الأصلي يرسل POST /api/files بـ body فارغ {} ويحصل على id
  /// رفع ملف حقيقي — نسخة مطابقة لـ create_ticket_page.dart التي تعمل
  Future<Map<String, String?>> uploadFileWithPath(String filePath) async {
    try {
      final uploadToken = await _auth.getAccessToken() ?? '';
      if (uploadToken.isEmpty) return {'id': null, 'error': 'لا يوجد توكن'};

      // محاولة 1: Multipart مع Origin header
      final request = http.MultipartRequest('POST', Uri.parse('$_baseUrl/files'));
      request.headers.addAll({
        'Authorization': 'Bearer $uploadToken',
        'Accept': 'application/json, text/plain, */*',
        'X-Client-App': '53d57a7f-3f89-4e9d-873b-3d071bc6dd9f',
        'X-User-Role': '0',
        'Origin': 'https://admin.ftth.iq',
        'Referer': 'https://admin.ftth.iq/',
      });
      request.files.add(await http.MultipartFile.fromPath('file', filePath));

      debugPrint('📁 uploading: $filePath');
      final streamResp = await request.send().timeout(const Duration(seconds: 30));
      final respBody = await streamResp.stream.bytesToString();
      debugPrint('📁 upload response: ${streamResp.statusCode} $respBody');

      if (streamResp.statusCode == 200 || streamResp.statusCode == 201) {
        final data = jsonDecode(respBody);
        final id = data['id']?.toString();
        if (id != null) return {'id': id, 'error': null};
      }

      // محاولة 2: JSON body فارغ (نفس طريقة الموقع بالضبط)
      debugPrint('📁 retry with JSON body...');
      final resp2 = await http.post(
        Uri.parse('$_baseUrl/files'),
        headers: {
          'Authorization': 'Bearer $uploadToken',
          'Accept': 'application/json, text/plain, */*',
          'X-Client-App': '53d57a7f-3f89-4e9d-873b-3d071bc6dd9f',
          'X-User-Role': '0',
          'Origin': 'https://admin.ftth.iq',
          'Referer': 'https://admin.ftth.iq/',
        },
        body: '{}',
      ).timeout(const Duration(seconds: 15));
      debugPrint('📁 retry response: ${resp2.statusCode} ${resp2.body}');

      if (resp2.statusCode == 200 || resp2.statusCode == 201) {
        final data = jsonDecode(resp2.body);
        final id = data['id']?.toString();
        if (id != null) return {'id': id, 'error': null};
      }

      return {'id': null, 'error': 'multipart: ${streamResp.statusCode}, json: ${resp2.statusCode}'};
    } catch (e) {
      debugPrint('⚠️ uploadFile error: $e');
      return {'id': null, 'error': '$e'};
    }
  }

  Future<String?> createFileId() async {
    final result = await uploadFileWithPath('');
    return result['id'];
  }

  /// رفع ملف فعلي (صورة) مع file path
  Future<String?> uploadFile(String filePath) async {
    try {
      final token = await _auth.getAccessToken();
      if (token == null) return null;

      final request = http.MultipartRequest('POST', Uri.parse('$_baseUrl/files'));
      request.headers.addAll({
        'Authorization': 'Bearer $token',
        ..._extraHeaders,
      });
      request.files.add(await http.MultipartFile.fromPath('file', filePath));
      final streamResp = await request.send();
      final respBody = await streamResp.stream.bytesToString();

      if (streamResp.statusCode == 200 || streamResp.statusCode == 201) {
        final data = jsonDecode(respBody);
        return data['id']?.toString();
      }
    } catch (e) {
      debugPrint('⚠️ uploadFile error: $e');
    }
    return null;
  }

  // ═══════════════════════════════════════════
  //  التحقق من رقم الهوية الوطنية
  //  GET مع query parameters (وليس POST)
  // ═══════════════════════════════════════════
  Future<Map<String, dynamic>> validateNationalId({
    required String idNumber,
    required String familyNumber,
    required String birthday,
    required String placeOfIssue,
    required String issuedAt,
    String? frontFileId,
    String? backFileId,
  }) async {
    try {
      final params = {
        'nationalId.idType.id': 'NationalId',
        'nationalId.idNumber': idNumber,
        'nationalId.pageNumber': '',
        'nationalId.bookNumber': '',
        'nationalId.familyNumber': familyNumber,
        'nationalId.officialDocument.frontFileId': frontFileId ?? '',
        'nationalId.officialDocument.backFileId': backFileId ?? '',
        'nationalId.placeOfIssue': placeOfIssue,
        'nationalId.issuedAt': issuedAt,
        'nationalId.birthday': birthday,
      };
      final query = params.entries
          .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
          .join('&');

      final resp = await _auth.authenticatedRequest(
        'GET',
        '$_baseUrl/requests/customer-onboarding/validate-national-id?$query',
        headers: _extraHeaders,
      );

      debugPrint('🔍 validateNationalId: status=${resp.statusCode}');
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final model = data['model'] ?? data;
        final isValid = model['isValid'] == true;
        return {
          'success': true,
          'isValid': isValid,
          'message': model['message'] ?? '',
        };
      }
      // عرض تفاصيل الخطأ
      debugPrint('🔍 validateNationalId error body: ${resp.body}');
      try {
        final err = jsonDecode(resp.body);
        final details = err['details'] ?? err['errors'] ?? [];
        final title = err['title'] ?? err['message'] ?? '';
        return {'success': false, 'isValid': false, 'error': '$title ${details is List ? details.join(", ") : details}'.trim()};
      } catch (_) {}
      return {'success': false, 'isValid': false, 'error': 'خطأ (${resp.statusCode}): ${resp.body.length > 200 ? resp.body.substring(0, 200) : resp.body}'};
    } catch (e) {
      return {'success': false, 'isValid': false, 'error': 'خطأ في الاتصال: $e'};
    }
  }

  // ═══════════════════════════════════════════
  //  إرسال طلب تسجيل مشترك جديد
  //  POST /api/requests/customer-onboarding
  // ═══════════════════════════════════════════
  Future<Map<String, dynamic>> submitOnboardingRequest({
    required Map<String, dynamic> requestBody,
  }) async {
    try {
      final resp = await _auth.authenticatedRequest(
        'POST',
        '$_baseUrl/requests/customer-onboarding',
        headers: {..._extraHeaders, 'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );
      if (resp.statusCode == 200 || resp.statusCode == 201) {
        final data = jsonDecode(resp.body);
        return {'success': true, 'data': data};
      }
      try {
        final err = jsonDecode(resp.body);
        return {
          'success': false,
          'error': err['message'] ?? err['title'] ?? 'فشل إرسال الطلب',
          'statusCode': resp.statusCode,
          'body': err,
        };
      } catch (_) {
        return {'success': false, 'error': 'فشل (${resp.statusCode})'};
      }
    } catch (e) {
      return {'success': false, 'error': 'خطأ في الاتصال: $e'};
    }
  }

  // ═══════════════════════════════════════════
  //  التحقق من OTP
  //  POST /api/requests/otp-validation
  // ═══════════════════════════════════════════
  Future<Map<String, dynamic>> validateOtp({
    required String phoneNumber,
    required String otp,
  }) async {
    try {
      final resp = await _auth.authenticatedRequest(
        'POST',
        '$_baseUrl/requests/otp-validation',
        headers: {..._extraHeaders, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'phoneNumber': phoneNumber,
          'otp': otp,
          'requestType': 0,
        }),
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        return {'success': true, 'isValid': data['isValid'] == true};
      }
      return {'success': false, 'error': 'فشل التحقق (${resp.statusCode})'};
    } catch (e) {
      return {'success': false, 'error': 'خطأ: $e'};
    }
  }

  // ═══════════════════════════════════════════
  //  جلب تفاصيل الطلب بعد الإنشاء
  // ═══════════════════════════════════════════
  Future<Map<String, dynamic>?> getRequestDetails(String requestId) async {
    try {
      final resp = await _auth.authenticatedRequest(
        'GET',
        '$_baseUrl/requests/customer-onboarding/$requestId',
        headers: _extraHeaders,
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        return data['model'] ?? data;
      }
    } catch (_) {}
    return null;
  }
}
