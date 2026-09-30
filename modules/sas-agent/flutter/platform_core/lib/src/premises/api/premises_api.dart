/// عميل REST لوحدة العقارات — فوق نواة الـ API المشتركة (توكن + عنوان الخادم).
///
/// منافذ المنصّة (تُستبدَل عند الاستخراج): ApiCore/Session/PlatformConfig.
library;

import 'package:http/http.dart' as http;

import '../../api/api_core.dart';
import '../../config.dart';
import '../../session.dart';
import '../models/premises.dart';

class PremisesApi {
  final ApiCore core;
  PremisesApi(this.core);

  Future<List<Premises>> list({
    String? q,
    String? propertyType,
    String? ownership,
    String? governorate,
    int page = 1,
    int count = 50,
  }) async {
    final r = await core.get('/api/premises', query: {
      'q': q,
      'property_type': propertyType,
      'ownership': ownership,
      'governorate': governorate,
      'page': '$page',
      'count': '$count',
    }) as Map<String, dynamic>;
    return ((r['premises'] as List?) ?? [])
        .map((e) => Premises.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Premises> get(int id) async =>
      Premises.fromJson(await core.get('/api/premises/$id') as Map<String, dynamic>);

  Future<Premises?> bySubscriber(int subscriberId) async {
    final r = await core.get('/api/premises/by-subscriber/$subscriberId') as Map<String, dynamic>;
    final p = r['premises'];
    return p == null ? null : Premises.fromJson(p as Map<String, dynamic>);
  }

  Future<Premises> create(Map<String, dynamic> body) async =>
      Premises.fromJson(await core.post('/api/premises', body) as Map<String, dynamic>);

  Future<Premises> update(int id, Map<String, dynamic> body) async =>
      Premises.fromJson(await core.patch('/api/premises/$id', body) as Map<String, dynamic>);

  Future<void> delete(int id) => core.delete('/api/premises/$id');

  /// اشتراكات ضمن النطاق للبحث عند الربط (كل عنصر: id/username/name/phone/premises_id).
  Future<List<Map<String, dynamic>>> linkCandidates({String q = '', int limit = 20}) async {
    final r = await core.get('/api/premises/link-candidates',
        query: {'q': q, 'limit': '$limit'}) as Map<String, dynamic>;
    return ((r['candidates'] as List?) ?? []).cast<Map<String, dynamic>>();
  }

  Future<void> link(int pid, List<int> subscriberIds) =>
      core.post('/api/premises/$pid/link', {'subscriber_ids': subscriberIds});

  Future<void> unlink(int pid, List<int> subscriberIds) =>
      core.post('/api/premises/$pid/unlink', {'subscriber_ids': subscriberIds});

  /// رفع صورة الدار (multipart) — ليست ضمن ApiCore، ننفّذها هنا بنفس التوكن/العنوان.
  Future<void> uploadPhoto(int pid, String filePath) async {
    final req = http.MultipartRequest('POST', Uri.parse('${core.base}/api/premises/$pid/photo'));
    if (Session.loggedIn) req.headers['Authorization'] = 'Bearer ${Session.token}';
    req.files.add(await http.MultipartFile.fromPath('file', filePath));
    final resp = await req.send().timeout(PlatformConfig.httpTimeout);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw ApiException(resp.statusCode, 'تعذّر رفع الصورة');
    }
  }

  /// رابط صورة الدار (للعرض عبر Image.network مع ترويسة التوكن أدناه).
  String photoUrl(int pid) => '${core.base}/api/premises/$pid/photo';

  Map<String, String> get authHeaders =>
      Session.loggedIn ? {'Authorization': 'Bearer ${Session.token}'} : const {};
}
