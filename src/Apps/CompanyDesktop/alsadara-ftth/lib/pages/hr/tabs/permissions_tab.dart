/// تبويب الصلاحيات — إدارة صلاحيات V2 للموظف
/// يعرض جميع الأنظمة مع إمكانية التعديل (view/add/edit/delete)
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../services/employee_profile_service.dart';

class PermissionsTab extends StatefulWidget {
  final String companyId;
  final String employeeId;
  final String employeeName;
  final bool canEdit;

  const PermissionsTab({
    super.key,
    required this.companyId,
    required this.employeeId,
    required this.employeeName,
    required this.canEdit,
  });

  @override
  State<PermissionsTab> createState() => _PermissionsTabState();
}

class _PermissionsTabState extends State<PermissionsTab> {
  final _service = EmployeeProfileService.instance;
  bool _loading = true;
  bool _saving = false;
  bool _editing = false;

  // النظام الأول V2 — firstSystemPermissionsV2
  Map<String, dynamic> _firstPerms = {};
  // النظام الثاني V2 — secondSystemPermissionsV2
  Map<String, dynamic> _secondPerms = {};

  static const _accent = Color(0xFF3498DB);
  static const _green = Color(0xFF27AE60);
  static const _red = Color(0xFFE74C3C);
  static const _gray = Color(0xFF95A5A6);

  // الأنظمة والأسماء المعروضة
  static const _firstSystemFeatures = {
    'attendance': 'الحضور والانصراف',
    'agent': 'الوكلاء',
    'customers': 'العملاء',
  };

  static const _secondSystemFeatures = {
    'users': 'المستخدمين',
    'subscriptions': 'الاشتراكات',
    'tasks': 'المهام',
    'accounts': 'الحسابات',
    'technicians': 'الفنيين',
    'transactions': 'المعاملات المالية',
    'reports': 'التقارير',
    'settings': 'الإعدادات',
    'notifications': 'الإشعارات',
    'accounting': 'المحاسبة',
  };

  static const _actions = ['view', 'add', 'edit', 'delete'];
  static const _actionLabels = {
    'view': 'عرض',
    'add': 'إضافة',
    'edit': 'تعديل',
    'delete': 'حذف',
  };
  static const _actionIcons = {
    'view': Icons.visibility,
    'add': Icons.add_circle,
    'edit': Icons.edit,
    'delete': Icons.delete,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _service.getEmployeePermissionsV2(
        widget.companyId,
        widget.employeeId,
      );
      if (data != null) {
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

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final perms = {
        'firstSystemPermissionsV2': json.encode(_firstPerms),
        'secondSystemPermissionsV2': json.encode(_secondPerms),
      };
      final ok = await _service.updateEmployeePermissionsV2(
        widget.companyId,
        widget.employeeId,
        perms,
      );
      if (ok && mounted) {
        setState(() => _editing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم حفظ الصلاحيات', style: GoogleFonts.cairo()),
            backgroundColor: _green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ: $e', style: GoogleFonts.cairo()),
            backgroundColor: _red,
          ),
        );
      }
    }
    setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _accent));
    }

    return Stack(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              _permSection(
                'النظام الأول',
                Icons.settings_applications,
                _firstSystemFeatures,
                _firstPerms,
                (feat, action, val) {
                  setState(() {
                    _firstPerms[feat] ??= {};
                    (_firstPerms[feat] as Map)[action] = val;
                  });
                },
              ),
              const SizedBox(height: 16),
              _permSection(
                'النظام الثاني',
                Icons.admin_panel_settings,
                _secondSystemFeatures,
                _secondPerms,
                (feat, action, val) {
                  setState(() {
                    _secondPerms[feat] ??= {};
                    (_secondPerms[feat] as Map)[action] = val;
                  });
                },
              ),
              const SizedBox(height: 80),
            ],
          ),
        ),
        // زر التعديل / الحفظ
        if (widget.canEdit)
          Positioned(
            left: 20,
            bottom: 20,
            child: Row(
              children: [
                if (_editing) ...[
                  FloatingActionButton.extended(
                    heroTag: 'perm_cancel',
                    onPressed: () {
                      setState(() => _editing = false);
                      _load();
                    },
                    backgroundColor: Colors.grey,
                    icon: const Icon(Icons.close, color: Colors.white),
                    label: Text('إلغاء',
                        style: GoogleFonts.cairo(color: Colors.white)),
                  ),
                  const SizedBox(width: 12),
                  FloatingActionButton.extended(
                    heroTag: 'perm_save',
                    onPressed: _saving ? null : _save,
                    backgroundColor: _green,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save, color: Colors.white),
                    label: Text('حفظ الصلاحيات',
                        style: GoogleFonts.cairo(color: Colors.white)),
                  ),
                ] else
                  FloatingActionButton.extended(
                    heroTag: 'perm_edit',
                    onPressed: () => setState(() => _editing = true),
                    backgroundColor: _accent,
                    icon: const Icon(Icons.edit, color: Colors.white),
                    label: Text('تعديل الصلاحيات',
                        style: GoogleFonts.cairo(color: Colors.white)),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _permSection(
    String title,
    IconData icon,
    Map<String, String> features,
    Map<String, dynamic> perms,
    void Function(String feature, String action, bool value) onToggle,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
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
                Icon(icon, color: _accent, size: 20),
                const SizedBox(width: 8),
                Text(title,
                    style: GoogleFonts.cairo(
                        fontWeight: FontWeight.bold, fontSize: 14)),
                const Spacer(),
                if (_editing) ...[
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        for (final f in features.keys) {
                          perms[f] = {
                            for (final a in _actions) a: true,
                          };
                        }
                      });
                    },
                    icon: const Icon(Icons.check_box, size: 16),
                    label: Text('تحديد الكل',
                        style: GoogleFonts.cairo(fontSize: 11)),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        for (final f in features.keys) {
                          perms[f] = {
                            for (final a in _actions) a: false,
                          };
                        }
                      });
                    },
                    icon: const Icon(Icons.check_box_outline_blank, size: 16),
                    label: Text('إلغاء الكل',
                        style: GoogleFonts.cairo(fontSize: 11)),
                  ),
                ],
              ],
            ),
          ),
          // Header row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: const Color(0xFFF8F9FA),
            child: Row(
              children: [
                SizedBox(
                  width: 140,
                  child: Text('النظام',
                      style: GoogleFonts.cairo(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: _gray)),
                ),
                ..._actions.map((a) => SizedBox(
                      width: 80,
                      child: Center(
                        child: Text(_actionLabels[a]!,
                            style: GoogleFonts.cairo(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: _gray)),
                      ),
                    )),
              ],
            ),
          ),
          ...features.entries.map((entry) {
            final feat = entry.key;
            final label = entry.value;
            final fp = perms[feat];
            final featurePerms =
                fp is Map ? Map<String, dynamic>.from(fp) : <String, dynamic>{};

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE))),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 140,
                    child: Text(label, style: GoogleFonts.cairo(fontSize: 12)),
                  ),
                  ..._actions.map((action) {
                    final enabled = featurePerms[action] == true;
                    return SizedBox(
                      width: 80,
                      child: Center(
                        child: _editing
                            ? Checkbox(
                                value: enabled,
                                activeColor: _green,
                                onChanged: (v) =>
                                    onToggle(feat, action, v ?? false),
                              )
                            : Icon(
                                enabled ? Icons.check_circle : Icons.cancel,
                                color: enabled ? _green : _red.withOpacity(0.3),
                                size: 20,
                              ),
                      ),
                    );
                  }),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
