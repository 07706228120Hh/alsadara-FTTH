/// تبويب الصلاحيات — ملخص سريع + زر فتح صفحة الإدارة الكاملة V2
/// يعرض ملخص الصلاحيات مع إمكانية فتح صفحة V2 للتعديل التفصيلي
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../permissions/permissions.dart';
import '../../../services/employee_profile_service.dart';
import '../../super_admin/permissions_management_v2_page.dart';

class PermissionsTab extends StatefulWidget {
  final String companyId;
  final String companyName;
  final String employeeId;
  final String employeeName;
  final bool canEdit;
  final VoidCallback? onPermissionsSaved;

  const PermissionsTab({
    super.key,
    required this.companyId,
    this.companyName = '',
    required this.employeeId,
    required this.employeeName,
    required this.canEdit,
    this.onPermissionsSaved,
  });

  @override
  State<PermissionsTab> createState() => _PermissionsTabState();
}

class _PermissionsTabState extends State<PermissionsTab> {
  final _service = EmployeeProfileService.instance;
  bool _loading = true;

  Map<String, dynamic> _firstPerms = {};
  Map<String, dynamic> _secondPerms = {};

  static const _accent = Color(0xFF9C27B0);
  static const _green = Color(0xFF27AE60);
  static const _red = Color(0xFFE74C3C);
  static const _gray = Color(0xFF95A5A6);
  static const _orange = Color(0xFFF39C12);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rawData = await _service.getEmployeePermissionsV2(
        widget.companyId,
        widget.employeeId,
      );
      if (rawData != null) {
        final data = rawData['data'] is Map
            ? Map<String, dynamic>.from(rawData['data'] as Map)
            : rawData;
        setState(() {
          final first = data['firstSystemPermissionsV2'] ??
              data['FirstSystemPermissionsV2'];
          final second = data['secondSystemPermissionsV2'] ??
              data['SecondSystemPermissionsV2'];
          _firstPerms = _parsePerms(first);
          _secondPerms = _parsePerms(second);
        });
      }
    } catch (_) {}
    setState(() => _loading = false);
  }

  Map<String, dynamic> _parsePerms(dynamic raw) {
    if (raw == null) return {};
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String) {
      try {
        return Map<String, dynamic>.from(json.decode(raw));
      } catch (_) {}
    }
    return {};
  }

  bool _getAction(Map<String, dynamic> perms, String key, String action) {
    final fp = perms[key];
    if (fp is Map) return fp[action] == true;
    return false;
  }

  /// فتح صفحة إدارة الصلاحيات V2 الكاملة
  Future<void> _openV2Page() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => PermissionsManagementV2Page(
          companyId: widget.companyId,
          companyName: widget.companyName,
          employeeId: widget.employeeId,
          employeeName: widget.employeeName,
        ),
      ),
    );
    if (result == true) {
      _load();
      widget.onPermissionsSaved?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFF9C27B0)));
    }

    // حساب الإحصائيات
    int totalFirst = 0, enabledFirst = 0;
    int totalSecond = 0, enabledSecond = 0;

    for (final e in PermissionRegistry.firstSystem) {
      if (e.isTopLevel) {
        totalFirst++;
        if (_getAction(_firstPerms, e.key, 'view')) enabledFirst++;
      }
    }
    for (final e in PermissionRegistry.secondSystem) {
      if (e.isTopLevel) {
        totalSecond++;
        if (_getAction(_secondPerms, e.key, 'view')) enabledSecond++;
      }
    }

    final totalAll = totalFirst + totalSecond;
    final enabledAll = enabledFirst + enabledSecond;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ═══ ملخص عام ═══
          _buildOverallSummary(enabledAll, totalAll),
          const SizedBox(height: 16),

          // ═══ ملخص النظامين ═══
          Row(
            children: [
              Expanded(
                child: _buildSystemSummary(
                  'النظام الرئيسي',
                  Icons.settings_applications_rounded,
                  enabledFirst,
                  totalFirst,
                  PermissionRegistry.firstSystem,
                  _firstPerms,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSystemSummary(
                  'نظام FTTH',
                  Icons.router_rounded,
                  enabledSecond,
                  totalSecond,
                  PermissionRegistry.secondSystem,
                  _secondPerms,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ═══ قائمة الصلاحيات المفعّلة ═══
          _buildEnabledPermsList(),
          const SizedBox(height: 24),

          // ═══ زر فتح صفحة الإدارة الكاملة ═══
          if (widget.canEdit)
            ElevatedButton.icon(
              onPressed: _openV2Page,
              icon: const Icon(Icons.security_rounded, size: 20),
              label: Text('إدارة الصلاحيات التفصيلية',
                  style: GoogleFonts.cairo(
                      fontWeight: FontWeight.bold, fontSize: 14)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
        ],
      ),
    );
  }

  /// ملخص عام — نسبة الصلاحيات الإجمالية
  Widget _buildOverallSummary(int enabled, int total) {
    final ratio = total > 0 ? enabled / total : 0.0;
    final color = ratio > 0.7 ? _green : (ratio > 0.3 ? _orange : _red);
    final percent = (ratio * 100).round();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_accent.withOpacity(0.1), _accent.withOpacity(0.03)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _accent.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            height: 64,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: ratio,
                  backgroundColor: Colors.grey.shade200,
                  color: color,
                  strokeWidth: 6,
                ),
                Text('$percent%',
                    style: GoogleFonts.cairo(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: color)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ملخص الصلاحيات',
                    style: GoogleFonts.cairo(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.black87)),
                const SizedBox(height: 4),
                Text('$enabled من $total صلاحية مفعّلة',
                    style: GoogleFonts.cairo(
                        fontSize: 13, color: Colors.black54)),
              ],
            ),
          ),
          Icon(Icons.shield_rounded, color: _accent.withOpacity(0.3), size: 40),
        ],
      ),
    );
  }

  /// ملخص نظام واحد
  Widget _buildSystemSummary(
    String title,
    IconData icon,
    int enabled,
    int total,
    List<PermissionEntry> entries,
    Map<String, dynamic> perms,
  ) {
    final ratio = total > 0 ? enabled / total : 0.0;
    final color = ratio > 0.7 ? _green : (ratio > 0.3 ? _orange : _red);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
              color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, color: _accent, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    style: GoogleFonts.cairo(
                        fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              value: ratio,
              backgroundColor: Colors.grey.shade200,
              color: color,
              strokeWidth: 5,
            ),
          ),
          const SizedBox(height: 8),
          Text('$enabled / $total',
              style: GoogleFonts.cairo(
                  fontWeight: FontWeight.bold, fontSize: 14)),
          Text('مفعّلة',
              style: GoogleFonts.cairo(fontSize: 10, color: _gray)),
        ],
      ),
    );
  }

  /// قائمة الصلاحيات المفعّلة (عرض سريع)
  Widget _buildEnabledPermsList() {
    final enabledPerms = <_PermInfo>[];

    for (final e in PermissionRegistry.firstSystem) {
      if (e.isTopLevel && _getAction(_firstPerms, e.key, 'view')) {
        final actions = <String>[];
        for (final a in ['view', 'add', 'edit', 'delete']) {
          if (_getAction(_firstPerms, e.key, a)) actions.add(_actionLabel(a));
        }
        enabledPerms.add(_PermInfo(e.labelAr, e.icon, actions, true));
      }
    }
    for (final e in PermissionRegistry.secondSystem) {
      if (e.isTopLevel && _getAction(_secondPerms, e.key, 'view')) {
        final actions = <String>[];
        for (final a in ['view', 'add', 'edit', 'delete']) {
          if (_getAction(_secondPerms, e.key, a)) actions.add(_actionLabel(a));
        }
        enabledPerms.add(_PermInfo(e.labelAr, e.icon, actions, false));
      }
    }

    if (enabledPerms.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          children: [
            Icon(Icons.block_rounded, color: _gray, size: 40),
            const SizedBox(height: 8),
            Text('لا توجد صلاحيات مفعّلة',
                style: GoogleFonts.cairo(color: _gray, fontSize: 13)),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
              color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: _accent.withOpacity(0.08),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle_outline_rounded,
                    color: _accent, size: 18),
                const SizedBox(width: 8),
                Text('الصلاحيات المفعّلة',
                    style: GoogleFonts.cairo(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: _accent)),
              ],
            ),
          ),
          ...enabledPerms.map((p) => Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: const BoxDecoration(
                  border:
                      Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
                ),
                child: Row(
                  children: [
                    Icon(p.icon, color: _accent, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.label,
                              style: GoogleFonts.cairo(
                                  fontWeight: FontWeight.w600, fontSize: 12)),
                          Text(p.actions.join(' • '),
                              style: GoogleFonts.cairo(
                                  fontSize: 10, color: _green)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: (p.isFirst ? Colors.blue : Colors.teal)
                            .withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        p.isFirst ? 'رئيسي' : 'FTTH',
                        style: GoogleFonts.cairo(
                          fontSize: 9,
                          color: p.isFirst ? Colors.blue : Colors.teal,
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

  String _actionLabel(String action) {
    const labels = {
      'view': 'عرض',
      'add': 'إضافة',
      'edit': 'تعديل',
      'delete': 'حذف',
    };
    return labels[action] ?? action;
  }
}

class _PermInfo {
  final String label;
  final IconData icon;
  final List<String> actions;
  final bool isFirst;
  _PermInfo(this.label, this.icon, this.actions, this.isFirst);
}
