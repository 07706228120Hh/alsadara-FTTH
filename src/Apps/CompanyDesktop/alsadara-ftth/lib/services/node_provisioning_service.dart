/// خدمة تجهيز العقدة (Node Provisioning)
///
/// مسؤولة عن جلب حزمة إعداد العقدة من الباك-إند وحفظها كملف JSON محلي.
///
/// **قابلية التوسّع**: هذه الخدمة هي نقطة التوسّع المركزية لكل ما يتعلق
/// بتجهيز العقد. المنطق (جلب/حفظ/بناء الحزمة) مفصول تماماً عن الواجهة،
/// بحيث يُعاد استخدامه لاحقاً في شاشات أخرى (مثل شاشة إدارة العقد،
/// أو معالج إعداد أوّلي، أو أدوات CLI داخلية).
///
/// TODO (ميزات مستقبلية — غير مُنفّذة الآن، البنية جاهزة لها):
///   - توليد مُثبِّت كامل (installer) للعقدة يتضمّن الإعدادات جاهزة.
///   - توليد رمز QR يحمل بيانات الحزمة لمسحها من جهاز العقدة.
///   - تضمين مزيد من الإعدادات (شهادات، عناوين MQTT، إصدار التهيئة...).
///   - التحقق من صحة الحزمة (validation) وتوقيعها قبل التسليم.
library;

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../models/node_config.dart';
import 'api/api_client.dart';
import 'api/api_config.dart';

class NodeProvisioningService {
  final ApiClient _client;

  /// يُستخدم [ApiClient.instance] افتراضياً (الذي يحمل توكن SuperAdmin بعد
  /// تسجيل الدخول)، ويمكن حقن عميل آخر للاختبار.
  NodeProvisioningService([ApiClient? client])
      : _client = client ?? ApiClient.instance;

  static const String _tag = 'NodeProvisioningService';

  /// جلب حزمة إعداد العقدة لشركة معيّنة.
  ///
  /// يستدعي `GET /api/superadmin/companies/{id}/node-config`
  /// **بتوكن SuperAdmin JWT** (الافتراضي — لا يستخدم internal key)،
  /// إذ إنّ الـ endpoint محمي بـ `[Authorize(Policy="SuperAdmin")]`.
  ///
  /// يُعيد [NodeConfig] عند النجاح، أو `null` عند الفشل.
  Future<NodeConfig?> fetchNodeConfig(String companyId) async {
    try {
      final response = await _client.get<NodeConfig>(
        ApiConfig.companyNodeConfig(companyId),
        (json) => NodeConfig.fromJson(json as Map<String, dynamic>),
        // ملاحظة أمنية: useInternalKey يبقى false عمداً كي يُرسَل توكن
        // SuperAdmin JWT وليس المفتاح الداخلي.
      );

      if (response.isSuccess && response.data != null) {
        return response.data;
      }

      if (kDebugMode) {
        debugPrint('$_tag: fetchNodeConfig failed - ${response.message}');
      }
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('$_tag: fetchNodeConfig error: $e');
      return null;
    }
  }

  /// حفظ حزمة الإعداد كملف `node.config.json` في موقع يختاره المستخدم.
  ///
  /// يستخدم نفس آلية الحفظ المعتمدة في المشروع:
  /// `FilePicker.platform.saveFile(...)` ثم `File(path).writeAsString(...)`.
  ///
  /// يُعيد مسار الملف المحفوظ عند النجاح، أو `null` إذا ألغى المستخدم
  /// الاختيار أو حدث خطأ.
  Future<String?> saveNodeConfigFile(NodeConfig config) async {
    try {
      // تنسيق JSON مقروء (مسافات بادئة) لسهولة قراءته يدوياً على العقدة.
      const encoder = JsonEncoder.withIndent('  ');
      final jsonString = encoder.convert(config.toJson());

      final defaultName = _buildFileName(config);

      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'حفظ حزمة إعداد العقدة',
        fileName: defaultName,
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (path == null) {
        if (kDebugMode) debugPrint('$_tag: user cancelled save');
        return null;
      }

      // بعض المنصّات قد لا تُلحق الامتداد؛ نضمن انتهاءه بـ .json
      final finalPath =
          path.toLowerCase().endsWith('.json') ? path : '$path.json';

      await File(finalPath).writeAsString(jsonString, flush: true);
      if (kDebugMode) debugPrint('$_tag: node config saved to $finalPath');
      return finalPath;
    } catch (e) {
      if (kDebugMode) debugPrint('$_tag: saveNodeConfigFile error: $e');
      return null;
    }
  }

  /// اسم الملف الافتراضي المقترح للحفظ.
  /// نقطة توسّع: يمكن تخصيص الصيغة لاحقاً (تضمين الإصدار، التاريخ...).
  String _buildFileName(NodeConfig config) {
    final safeNode = config.nodeId.isNotEmpty ? config.nodeId : 'node';
    return 'node.config.$safeNode.json';
  }
}
