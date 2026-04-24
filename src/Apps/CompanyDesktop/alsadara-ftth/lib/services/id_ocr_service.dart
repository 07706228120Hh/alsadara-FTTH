import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../services/api/api_config.dart';

/// خدمة OCR — ترسل صورة الهوية للسيرفر ويرجع البيانات المستخرجة
class IdOcrService {
  /// استخراج بيانات الهوية من صورتين (أمامية + خلفية) دفعة واحدة
  static Future<Map<String, dynamic>?> extractBothSides({
    required String? frontPath,
    required String? backPath,
  }) async {
    if (frontPath == null && backPath == null) return null;
    try {
      final url = '${ApiConfig.baseUrl}/ocr/id-card-both';
      final request = http.MultipartRequest('POST', Uri.parse(url));

      if (frontPath != null) {
        request.files.add(await http.MultipartFile.fromPath('front', frontPath));
      }
      if (backPath != null) {
        request.files.add(await http.MultipartFile.fromPath('back', backPath));
      }

      debugPrint('📷 OCR sending: front=${frontPath != null}, back=${backPath != null}');
      final streamResp = await request.send().timeout(const Duration(seconds: 120));
      final respBody = await streamResp.stream.bytesToString();

      debugPrint('📷 OCR response: ${streamResp.statusCode}');
      debugPrint('📷 OCR body: $respBody');

      if (streamResp.statusCode == 200) {
        final data = jsonDecode(respBody) as Map<String, dynamic>;
        // نقبل أي نتيجة فيها حقول مفيدة
        final hasFields = data.keys.any((k) => k != 'rawText' && k != 'success');
        if (hasFields) return data;
        if (data['success']?.toString() == 'true') return data;
      }

      debugPrint('⚠️ OCR failed: $respBody');
      return null;
    } catch (e) {
      debugPrint('⚠️ OCR error: $e');
      return null;
    }
  }
}
