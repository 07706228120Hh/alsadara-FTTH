/// نموذج حزمة إعداد العقدة (Node Config)
///
/// يمثّل الحزمة التي يُعيدها الـ endpoint:
///   GET /api/superadmin/companies/{id}/node-config
///   { "success": true, "data": { company_id, company_name, node_id, gateway_url, jwks_url } }
///
/// صُمّم النموذج ليكون **قابلاً للتوسّع**:
/// - كل حقل جديد يضيفه الباك-إند مستقبلاً يُحفظ تلقائياً في [extra]
///   دون كسر التطبيقات القديمة، ويُكتب ضمن ملف الـ JSON عبر [toJson].
/// - لإضافة حقل مُصرّح به (typed) لاحقاً: أضِف الحقل + قراءته في [fromJson]
///   + كتابته في [toJson] فقط، دون لمس بقية الكود.
library;

class NodeConfig {
  /// معرّف الشركة (company_id)
  final String companyId;

  /// اسم الشركة (company_name)
  final String companyName;

  /// معرّف العقدة (node_id)
  final String nodeId;

  /// رابط البوّابة (gateway_url)
  final String gatewayUrl;

  /// رابط مفاتيح JWKS (jwks_url)
  final String jwksUrl;

  /// حقول إضافية غير مُصرّح بها هنا، محفوظة كما وردت من الخادم.
  /// نقطة توسّع: تُبقي الحزمة متوافقة مع أي حقول جديدة يضيفها الباك-إند
  /// مستقبلاً (مثل: mqtt_url, cert_fingerprint, config_version ...).
  final Map<String, dynamic> extra;

  const NodeConfig({
    required this.companyId,
    required this.companyName,
    required this.nodeId,
    required this.gatewayUrl,
    required this.jwksUrl,
    this.extra = const {},
  });

  /// المفاتيح المُصرّح بها (typed) — تُستبعد من [extra].
  static const Set<String> _knownKeys = {
    'company_id',
    'company_name',
    'node_id',
    'gateway_url',
    'jwks_url',
  };

  /// إنشاء من JSON (يدعم snake_case القادم من الباك-إند مع fallback إلى camelCase).
  factory NodeConfig.fromJson(Map<String, dynamic> json) {
    // أي مفتاح غير معروف يُحفظ في extra للتوافق المستقبلي
    final extra = <String, dynamic>{};
    for (final entry in json.entries) {
      if (!_knownKeys.contains(entry.key) &&
          !_camelAliases.contains(entry.key)) {
        extra[entry.key] = entry.value;
      }
    }

    return NodeConfig(
      companyId:
          (json['company_id'] ?? json['companyId'] ?? '').toString(),
      companyName:
          (json['company_name'] ?? json['companyName'] ?? '').toString(),
      nodeId: (json['node_id'] ?? json['nodeId'] ?? '').toString(),
      gatewayUrl:
          (json['gateway_url'] ?? json['gatewayUrl'] ?? '').toString(),
      jwksUrl: (json['jwks_url'] ?? json['jwksUrl'] ?? '').toString(),
      extra: extra,
    );
  }

  /// أسماء camelCase البديلة التي نتجاهلها عند بناء [extra].
  static const Set<String> _camelAliases = {
    'companyId',
    'companyName',
    'nodeId',
    'gatewayUrl',
    'jwksUrl',
  };

  /// تحويل إلى JSON لكتابته كملف `node.config.json`.
  /// يُبقي التنسيق snake_case المطابق لعقد الباك-إند، ويُضمّن أي حقول إضافية.
  Map<String, dynamic> toJson() => {
        'company_id': companyId,
        'company_name': companyName,
        'node_id': nodeId,
        'gateway_url': gatewayUrl,
        'jwks_url': jwksUrl,
        ...extra,
      };

  @override
  String toString() =>
      'NodeConfig(companyId: $companyId, nodeId: $nodeId, gatewayUrl: $gatewayUrl)';
}
