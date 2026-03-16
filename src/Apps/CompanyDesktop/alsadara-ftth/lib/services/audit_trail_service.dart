import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'vps_auth_service.dart';

/// أنواع العمليات في سجل التدقيق
enum AuditAction {
  create,
  edit,
  delete,
  post,
  void_,
  closePeriod,
  reopenPeriod,
}

/// أنواع الكيانات المتتبعة
enum AuditEntityType {
  journalEntry,
  expense,
  salary,
  collection,
  cashBox,
  period,
  fixedExpense,
}

/// خدمة سجل التدقيق المحلي
/// التخزين: ملف JSON في مجلد المستندات
class AuditTrailService {
  AuditTrailService._internal();
  static AuditTrailService? _instance;
  static AuditTrailService get instance =>
      _instance ??= AuditTrailService._internal();

  List<Map<String, dynamic>> _records = [];
  String? _currentCompanyId;
  bool _dirty = false;

  static const int _maxRecords = 10000;

  // ─── أسماء عربية ───
  static const actionLabels = {
    AuditAction.create: 'إنشاء',
    AuditAction.edit: 'تعديل',
    AuditAction.delete: 'حذف',
    AuditAction.post: 'ترحيل',
    AuditAction.void_: 'إلغاء',
    AuditAction.closePeriod: 'إقفال فترة',
    AuditAction.reopenPeriod: 'إعادة فتح فترة',
  };

  static const entityLabels = {
    AuditEntityType.journalEntry: 'قيد محاسبي',
    AuditEntityType.expense: 'مصروف',
    AuditEntityType.salary: 'راتب',
    AuditEntityType.collection: 'تحصيل',
    AuditEntityType.cashBox: 'صندوق',
    AuditEntityType.period: 'فترة',
    AuditEntityType.fixedExpense: 'مصروف ثابت',
  };

  // ─── مسار الملف ───
  Future<String> _filePath(String companyId) async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/alsadara_audit/$companyId');
    if (!folder.existsSync()) folder.createSync(recursive: true);
    return '${folder.path}/audit.json';
  }

  // ─── تهيئة ───
  Future<void> initialize(String companyId) async {
    if (_currentCompanyId == companyId && _records.isNotEmpty) return;
    _currentCompanyId = companyId;
    await _load(companyId);
  }

  // ─── تحميل من الملف ───
  Future<void> _load(String companyId) async {
    try {
      final path = await _filePath(companyId);
      final file = File(path);
      if (file.existsSync()) {
        final json = file.readAsStringSync();
        final List<dynamic> list = jsonDecode(json);
        _records = list.cast<Map<String, dynamic>>();
      } else {
        _records = [];
      }
    } catch (_) {
      _records = [];
    }
  }

  // ─── حفظ إلى الملف ───
  Future<void> _save() async {
    if (!_dirty || _currentCompanyId == null) return;
    try {
      final path = await _filePath(_currentCompanyId!);
      File(path).writeAsStringSync(jsonEncode(_records));
      _dirty = false;
    } catch (_) {}
  }

  // ─── تسجيل عملية ───
  Future<void> log({
    required AuditAction action,
    required AuditEntityType entityType,
    required String entityId,
    String? entityDescription,
    String? details,
    String? companyId,
  }) async {
    final cid = companyId ??
        _currentCompanyId ??
        VpsAuthService.instance.currentCompanyId ??
        '';

    if (_currentCompanyId != cid) {
      await initialize(cid);
    }

    final record = <String, dynamic>{
      'timestamp': DateTime.now().toIso8601String(),
      'userId': VpsAuthService.instance.currentUser?.id ?? '',
      'userName': VpsAuthService.instance.currentUser?.fullName ?? '',
      'action': action.name,
      'entityType': entityType.name,
      'entityId': entityId,
      'entityDescription': entityDescription ?? '',
      'details': details ?? '',
      'companyId': cid,
    };

    _records.insert(0, record);

    // حد أقصى
    if (_records.length > _maxRecords) {
      _records = _records.sublist(0, _maxRecords);
    }

    _dirty = true;
    await _save();
  }

  // ─── جلب السجلات ───
  List<Map<String, dynamic>> getRecords({
    AuditAction? action,
    AuditEntityType? entityType,
    DateTime? fromDate,
    DateTime? toDate,
  }) {
    var list = List<Map<String, dynamic>>.from(_records);

    if (action != null) {
      list = list.where((r) => r['action'] == action.name).toList();
    }
    if (entityType != null) {
      list = list.where((r) => r['entityType'] == entityType.name).toList();
    }
    if (fromDate != null) {
      list = list.where((r) {
        final ts = DateTime.tryParse(r['timestamp'] ?? '');
        return ts != null && !ts.isBefore(fromDate);
      }).toList();
    }
    if (toDate != null) {
      final end = toDate.add(const Duration(days: 1));
      list = list.where((r) {
        final ts = DateTime.tryParse(r['timestamp'] ?? '');
        return ts != null && ts.isBefore(end);
      }).toList();
    }

    return list;
  }

  /// عدد السجلات الإجمالي
  int get totalRecords => _records.length;
}
