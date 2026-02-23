/// تبويب الصلاحيات V3 — عرض هرمي شامل لصلاحيات الموظف
/// يستخدم PermissionRegistry كمصدر وحيد للحقيقة
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../permissions/permissions.dart';
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
  String? _selectedTemplate;

  // النظام الأول V2 — firstSystemPermissionsV2
  Map<String, dynamic> _firstPerms = {};
  // النظام الثاني V2 — secondSystemPermissionsV2
  Map<String, dynamic> _secondPerms = {};

  static const _accent = Color(0xFF3498DB);
  static const _green = Color(0xFF27AE60);
  static const _red = Color(0xFFE74C3C);
  static const _gray = Color(0xFF95A5A6);
  static const _orange = Color(0xFFF39C12);

  // جميع الإجراءات الممكنة
  static const _allActions = [
    'view',
    'add',
    'edit',
    'delete',
    'export',
    'import',
    'print',
    'send'
  ];
  static const _actionLabels = {
    'view': 'عرض',
    'add': 'إضافة',
    'edit': 'تعديل',
    'delete': 'حذف',
    'export': 'تصدير',
    'import': 'استيراد',
    'print': 'طباعة',
    'send': 'إرسال',
  };
  static const _actionIcons = {
    'view': Icons.visibility,
    'add': Icons.add_circle,
    'edit': Icons.edit,
    'delete': Icons.delete,
    'export': Icons.file_download,
    'import': Icons.file_upload,
    'print': Icons.print,
    'send': Icons.send,
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

  bool _getAction(Map<String, dynamic> perms, String key, String action) {
    final fp = perms[key];
    if (fp is Map) return fp[action] == true;
    return false;
  }

  void _setAction(
      Map<String, dynamic> perms, String key, String action, bool value) {
    perms[key] ??= <String, dynamic>{};
    (perms[key] as Map)[action] = value;
  }

  /// تفعيل/إلغاء مفتاح رئيسي مع جميع أبنائه
  void _toggleParent(Map<String, dynamic> perms, String parentKey, bool value,
      List<PermissionEntry> children) {
    // تفعيل/إلغاء جميع الإجراءات للأب
    final parentEntry = PermissionRegistry.findByKey(parentKey);
    final parentActions = parentEntry?.allowedActions ?? _allActions;
    for (final a in parentActions) {
      _setAction(perms, parentKey, a, value);
    }
    // تفعيل/إلغاء جميع الأبناء
    for (final child in children) {
      final childActions = child.allowedActions ?? _allActions;
      for (final a in childActions) {
        _setAction(perms, child.key, a, value);
      }
    }
  }

  /// تطبيق قالب صلاحيات
  void _applyTemplate(String templateName) {
    final template = PermissionRegistry.getTemplate(templateName);
    setState(() {
      _selectedTemplate = templateName;
      // مسح الصلاحيات القديمة
      _firstPerms.clear();
      _secondPerms.clear();

      for (final entry in template.entries) {
        final key = entry.key;
        final actions = entry.value['actions'] ?? [];
        final actionMap = <String, dynamic>{};
        for (final a in _allActions) {
          actionMap[a] = actions.contains(a);
        }

        // حدد أي نظام ينتمي إليه المفتاح
        final isFirst = PermissionRegistry.firstSystem.any((e) => e.key == key);
        if (isFirst) {
          _firstPerms[key] = actionMap;
        } else {
          _secondPerms[key] = actionMap;
        }
      }
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      // إرسال المفاتيح كـ objects وليس JSON strings
      final perms = {
        'firstSystemPermissionsV2': _firstPerms,
        'secondSystemPermissionsV2': _secondPerms,
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
            content: Text('تم حفظ الصلاحيات بنجاح', style: GoogleFonts.cairo()),
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
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // شريط القوالب الجاهزة
              if (_editing) _buildTemplateBar(),
              const SizedBox(height: 12),
              // ملخص الصلاحيات
              _buildPermSummary(),
              const SizedBox(height: 16),
              // النظام الأول
              _buildHierarchicalSection(
                'النظام الأول — الرئيسي',
                Icons.settings_applications_rounded,
                PermissionRegistry.firstSystem,
                _firstPerms,
                isFirst: true,
              ),
              const SizedBox(height: 16),
              // النظام الثاني — FTTH
              _buildHierarchicalSection(
                'النظام الثاني — FTTH',
                Icons.router_rounded,
                PermissionRegistry.secondSystem,
                _secondPerms,
                isFirst: false,
              ),
            ],
          ),
        ),
        // أزرار التعديل / الحفظ
        if (widget.canEdit) _buildActionButtons(),
      ],
    );
  }

  /// شريط القوالب الجاهزة
  Widget _buildTemplateBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _orange.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _orange.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.flash_on_rounded, color: _orange, size: 18),
              const SizedBox(width: 6),
              Text('قوالب جاهزة — تطبيق سريع',
                  style: GoogleFonts.cairo(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: _orange)),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: PermissionRegistry.templateNames.entries.map((e) {
              final selected = _selectedTemplate == e.key;
              return ActionChip(
                avatar: Icon(
                  selected ? Icons.check_circle : Icons.person_outline,
                  size: 16,
                  color: selected ? Colors.white : _accent,
                ),
                label: Text(e.value,
                    style: GoogleFonts.cairo(
                      fontSize: 11,
                      color: selected ? Colors.white : Colors.black87,
                    )),
                backgroundColor: selected ? _accent : Colors.white,
                side: BorderSide(
                    color: selected ? _accent : Colors.grey.shade300),
                onPressed: () => _applyTemplate(e.key),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  /// ملخص الصلاحيات — عدد المفعّلة
  Widget _buildPermSummary() {
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

    return Row(
      children: [
        Expanded(
          child: _summaryChip(
              'النظام الأول', enabledFirst, totalFirst, Icons.apps_rounded),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _summaryChip('النظام الثاني', enabledSecond, totalSecond,
              Icons.router_rounded),
        ),
      ],
    );
  }

  Widget _summaryChip(String label, int enabled, int total, IconData icon) {
    final ratio = total > 0 ? enabled / total : 0.0;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 3, offset: Offset(0, 1)),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: _accent, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: GoogleFonts.cairo(fontSize: 11, color: _gray)),
                Text('$enabled / $total مفعّل',
                    style: GoogleFonts.cairo(
                        fontWeight: FontWeight.bold, fontSize: 13)),
              ],
            ),
          ),
          SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              value: ratio,
              backgroundColor: Colors.grey.shade200,
              color: ratio > 0.7 ? _green : (ratio > 0.3 ? _orange : _red),
              strokeWidth: 4,
            ),
          ),
        ],
      ),
    );
  }

  /// بناء قسم هرمي (النظام الأول أو الثاني)
  Widget _buildHierarchicalSection(
    String title,
    IconData icon,
    List<PermissionEntry> entries,
    Map<String, dynamic> perms, {
    required bool isFirst,
  }) {
    final grouped = PermissionRegistry.getGrouped(entries);

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
          // عنوان القسم
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
                  _miniButton('تفعيل الكل', Icons.check_box, () {
                    setState(() {
                      for (final e in entries) {
                        final actions = e.allowedActions ?? _allActions;
                        for (final a in actions) {
                          _setAction(perms, e.key, a, true);
                        }
                      }
                    });
                  }),
                  const SizedBox(width: 4),
                  _miniButton('إلغاء الكل', Icons.check_box_outline_blank, () {
                    setState(() {
                      for (final e in entries) {
                        for (final a in _allActions) {
                          _setAction(perms, e.key, a, false);
                        }
                      }
                    });
                  }),
                ],
              ],
            ),
          ),
          // العناصر
          ...grouped.entries.map((group) {
            final parent = group.key;
            final children = group.value;
            return _buildPermGroup(parent, children, perms);
          }),
        ],
      ),
    );
  }

  /// مجموعة صلاحيات (أب + أبناء)
  Widget _buildPermGroup(PermissionEntry parent, List<PermissionEntry> children,
      Map<String, dynamic> perms) {
    final hasChildren = children.isNotEmpty;
    final parentHasView = _getAction(perms, parent.key, 'view');

    // حساب عدد المفعّلة من الأبناء
    int enabledChildren = 0;
    for (final child in children) {
      if (_getAction(perms, child.key, 'view')) enabledChildren++;
    }

    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE))),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
          childrenPadding: EdgeInsets.zero,
          leading: Icon(parent.icon,
              color: parentHasView ? _accent : _gray, size: 22),
          title: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(parent.labelAr,
                        style: GoogleFonts.cairo(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color:
                              parentHasView ? Colors.black87 : Colors.black45,
                        )),
                    if (hasChildren)
                      Text(
                        '$enabledChildren/${children.length} فرعي مفعّل',
                        style: GoogleFonts.cairo(
                            fontSize: 10,
                            color: enabledChildren > 0 ? _green : _gray),
                      ),
                  ],
                ),
              ),
            ],
          ),
          trailing: _editing
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hasChildren) ...[
                      // زر تفعيل/إلغاء الكل للأب وأبنائه
                      IconButton(
                        icon: Icon(
                          parentHasView
                              ? Icons.toggle_on_rounded
                              : Icons.toggle_off_rounded,
                          color: parentHasView ? _green : _gray,
                          size: 28,
                        ),
                        tooltip: parentHasView ? 'إلغاء الكل' : 'تفعيل الكل',
                        onPressed: () {
                          setState(() {
                            _toggleParent(
                                perms, parent.key, !parentHasView, children);
                          });
                        },
                      ),
                    ],
                    // إجراءات الأب المباشرة
                    ..._buildActionChips(perms, parent),
                  ],
                )
              : _buildReadOnlyActions(perms, parent),
          children: [
            if (hasChildren) ...[
              // عنوان فرعي
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 40, vertical: 4),
                color: const Color(0xFFF8F9FA),
                child: Row(
                  children: [
                    SizedBox(
                      width: 160,
                      child: Text('الميزة الفرعية',
                          style: GoogleFonts.cairo(
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                              color: _gray)),
                    ),
                    ..._allActions.map((a) => SizedBox(
                          width: 52,
                          child: Center(
                            child: Text(_actionLabels[a]!,
                                style: GoogleFonts.cairo(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 10,
                                    color: _gray)),
                          ),
                        )),
                  ],
                ),
              ),
              // صفوف الأبناء
              ...children.map((child) => _buildChildRow(child, perms)),
            ],
          ],
        ),
      ),
    );
  }

  /// صف ابن فرعي مع جميع الإجراءات
  Widget _buildChildRow(PermissionEntry child, Map<String, dynamic> perms) {
    final allowedActions = child.allowedActions ?? _allActions;
    final hasView = _getAction(perms, child.key, 'view');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 4),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF5F5F5))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 160,
            child: Row(
              children: [
                Icon(child.icon,
                    size: 16,
                    color: hasView ? _accent : _gray.withOpacity(0.5)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(child.labelAr,
                      style: GoogleFonts.cairo(
                        fontSize: 11,
                        color: hasView ? Colors.black87 : Colors.black45,
                      )),
                ),
              ],
            ),
          ),
          ..._allActions.map((action) {
            final allowed = allowedActions.contains(action);
            if (!allowed) {
              return const SizedBox(width: 52);
            }
            final enabled = _getAction(perms, child.key, action);
            return SizedBox(
              width: 52,
              child: Center(
                child: _editing
                    ? SizedBox(
                        width: 28,
                        height: 28,
                        child: Checkbox(
                          value: enabled,
                          activeColor: _green,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          onChanged: (v) {
                            setState(() {
                              _setAction(perms, child.key, action, v ?? false);
                            });
                          },
                        ),
                      )
                    : Icon(
                        enabled ? Icons.check_circle : Icons.cancel,
                        color: enabled ? _green : _red.withOpacity(0.2),
                        size: 16,
                      ),
              ),
            );
          }),
        ],
      ),
    );
  }

  /// رقائق الإجراءات للمفتاح الرئيسي (وضع التعديل)
  List<Widget> _buildActionChips(
      Map<String, dynamic> perms, PermissionEntry entry) {
    final allowedActions = entry.allowedActions ?? _allActions;
    // عرض أول 4 إجراءات أساسية فقط للأب (المساحة محدودة)
    final shownActions = allowedActions
        .where((a) => ['view', 'add', 'edit', 'delete'].contains(a))
        .toList();

    return shownActions.map((action) {
      final enabled = _getAction(perms, entry.key, action);
      return Padding(
        padding: const EdgeInsets.only(left: 2),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () {
            setState(() {
              _setAction(perms, entry.key, action, !enabled);
            });
          },
          child: Tooltip(
            message: _actionLabels[action]!,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: enabled
                    ? _green.withOpacity(0.15)
                    : Colors.grey.withOpacity(0.08),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(
                _actionIcons[action],
                size: 14,
                color: enabled ? _green : _gray.withOpacity(0.5),
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  /// عرض القراءة فقط للإجراءات
  Widget _buildReadOnlyActions(
      Map<String, dynamic> perms, PermissionEntry entry) {
    final allowedActions = entry.allowedActions ?? _allActions;
    final shownActions = allowedActions
        .where((a) => ['view', 'add', 'edit', 'delete'].contains(a))
        .toList();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: shownActions.map((action) {
        final enabled = _getAction(perms, entry.key, action);
        return Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Tooltip(
            message: _actionLabels[action]!,
            child: Icon(
              enabled ? Icons.check_circle : Icons.cancel,
              size: 16,
              color: enabled ? _green : _red.withOpacity(0.2),
            ),
          ),
        );
      }).toList(),
    );
  }

  /// زر مصغر
  Widget _miniButton(String label, IconData icon, VoidCallback onPressed) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 14),
      label: Text(label, style: GoogleFonts.cairo(fontSize: 10)),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  /// أزرار التعديل / الحفظ / الإلغاء
  Widget _buildActionButtons() {
    return Positioned(
      left: 20,
      bottom: 20,
      child: Row(
        children: [
          if (_editing) ...[
            FloatingActionButton.extended(
              heroTag: 'perm_cancel',
              onPressed: () {
                setState(() {
                  _editing = false;
                  _selectedTemplate = null;
                });
                _load();
              },
              backgroundColor: Colors.grey,
              icon: const Icon(Icons.close, color: Colors.white),
              label:
                  Text('إلغاء', style: GoogleFonts.cairo(color: Colors.white)),
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
    );
  }
}
