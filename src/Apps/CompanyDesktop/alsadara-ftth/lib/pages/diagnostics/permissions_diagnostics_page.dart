/// صفحة تشخيص الصلاحيات — فحص شامل لنظام الصلاحيات
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../permissions/permissions.dart';
import '../../services/vps_auth_service.dart';

/// صفحة تشخيص الصلاحيات
class PermissionsDiagnosticsPage extends StatelessWidget {
  const PermissionsDiagnosticsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text('تشخيص الصلاحيات',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
          centerTitle: true,
          backgroundColor: Colors.indigo,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(Icons.copy_all),
              onPressed: () => _copyAllDiagnostics(context),
              tooltip: 'نسخ الكل',
            ),
          ],
        ),
        body: const _DiagnosticsBody(),
      ),
    );
  }

  void _copyAllDiagnostics(BuildContext context) {
    final pm = PermissionManager.instance;
    final auth = VpsAuthService.instance;
    final user = auth.currentUser;
    final company = auth.currentCompany;
    final buf = StringBuffer();

    buf.writeln('══════════════════════════════════════');
    buf.writeln('تقرير تشخيص الصلاحيات');
    buf.writeln('التاريخ: ${DateTime.now()}');
    buf.writeln('══════════════════════════════════════\n');

    // ملخص
    final totalRegistry = PermissionRegistry.firstSystem.length +
        PermissionRegistry.secondSystem.length;
    final grantedFirst = pm.firstSystemPermissions.values
        .where((v) => v['view'] == true).length;
    final grantedSecond = pm.secondSystemPermissions.values
        .where((v) => v['view'] == true).length;
    final totalGranted = grantedFirst + grantedSecond;
    final coverage = totalRegistry > 0
        ? (totalGranted / totalRegistry * 100).toStringAsFixed(1)
        : '0';

    buf.writeln('=== ملخص عام ===');
    buf.writeln('المستخدم: ${user?.fullName ?? "غير معروف"}');
    buf.writeln('الدور: ${user?.role ?? "-"}');
    buf.writeln('مدير شركة: ${user?.isAdmin == true ? "نعم" : "لا"}');
    buf.writeln('إجمالي الصلاحيات: $totalRegistry');
    buf.writeln('ممنوحة: $totalGranted | محجوبة: ${totalRegistry - totalGranted}');
    buf.writeln('نسبة التغطية: $coverage%');

    // النظام الأول
    buf.writeln('\n=== النظام الأول ===');
    _writeSystemPerms(buf, PermissionRegistry.firstSystem, pm.firstSystemPermissions);

    // النظام الثاني
    buf.writeln('\n=== النظام الثاني (FTTH) ===');
    _writeSystemPerms(buf, PermissionRegistry.secondSystem, pm.secondSystemPermissions);

    // مشاكل
    final issues = _findIssuesStatic(pm, company);
    buf.writeln('\n=== مشاكل محتملة (${issues.length}) ===');
    if (issues.isEmpty) {
      buf.writeln('لا توجد مشاكل');
    } else {
      for (final issue in issues) {
        final prefix = switch (issue.type) {
          _IssueType.error => '[خطأ]',
          _IssueType.warning => '[تحذير]',
          _IssueType.info => '[معلومة]',
        };
        buf.writeln('$prefix ${issue.title}');
        buf.writeln('  ${issue.detail.replaceAll('\n', '\n  ')}');
      }
    }

    Clipboard.setData(ClipboardData(text: buf.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم نسخ تقرير التشخيص الكامل'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );
  }

  static void _writeSystemPerms(StringBuffer buf,
      List<PermissionEntry> entries,
      Map<String, Map<String, bool>> permissions) {
    final grouped = PermissionRegistry.getGrouped(entries);
    for (final entry in grouped.entries) {
      final parent = entry.key;
      final children = entry.value;
      final pPerms = permissions[parent.key] ?? {};
      final viewStr = pPerms['view'] == true ? 'مسموح' : 'ممنوع';
      buf.writeln('${parent.labelAr} (${parent.key}): $viewStr');
      for (final child in children) {
        final cPerms = permissions[child.key] ?? {};
        final inherited = !permissions.containsKey(child.key);
        final cView = inherited
            ? (pPerms['view'] == true ? 'وارث' : 'ممنوع')
            : (cPerms['view'] == true ? 'مسموح' : 'ممنوع');
        buf.writeln('  ├─ ${child.labelAr} (${child.key}): $cView');
      }
    }
  }

  static List<_DiagIssue> _findIssuesStatic(
      PermissionManager pm, VpsCompanyInfo? company) {
    // نفس منطق _DiagnosticsBody._findIssues
    final issues = <_DiagIssue>[];
    final firstPerms = pm.firstSystemPermissions;
    final secondPerms = pm.secondSystemPermissions;

    for (final entry in PermissionRegistry.firstSystem) {
      if (entry.isTopLevel && !firstPerms.containsKey(entry.key)) {
        issues.add(_DiagIssue(type: _IssueType.warning,
            title: 'صلاحية غير موجودة في بيانات المستخدم',
            detail: '${entry.labelAr} (${entry.key}) — النظام الأول'));
      }
    }
    for (final entry in PermissionRegistry.secondSystem) {
      if (!secondPerms.containsKey(entry.key)) {
        issues.add(_DiagIssue(type: _IssueType.warning,
            title: 'صلاحية غير موجودة في بيانات المستخدم',
            detail: '${entry.labelAr} (${entry.key}) — النظام الثاني'));
      }
    }
    for (final key in firstPerms.keys) {
      if (PermissionRegistry.findByKey(key) == null) {
        issues.add(_DiagIssue(type: _IssueType.warning,
            title: 'صلاحية غير معروفة', detail: '$key — النظام الأول'));
      }
    }
    for (final key in secondPerms.keys) {
      if (PermissionRegistry.findByKey(key) == null) {
        issues.add(_DiagIssue(type: _IssueType.warning,
            title: 'صلاحية غير معروفة', detail: '$key — النظام الثاني'));
      }
    }
    for (final entry in PermissionRegistry.firstSystem) {
      if (entry.parent != null) {
        final parentPerms = firstPerms[entry.parent!];
        final childPerms = firstPerms[entry.key];
        if (parentPerms != null && parentPerms['view'] != true &&
            childPerms != null && childPerms['view'] == true) {
          issues.add(_DiagIssue(type: _IssueType.error,
              title: 'تناقض هرمي',
              detail: '${entry.labelAr} مسموح لكن الأب (${entry.parent}) ممنوع'));
        }
      }
    }
    if (company != null) {
      for (final e in company.enabledFirstSystemFeatures.entries) {
        if (e.value == true && !pm.canView(e.key)) {
          final reg = PermissionRegistry.findByKey(e.key);
          if (reg != null) {
            issues.add(_DiagIssue(type: _IssueType.info,
                title: 'ميزة مفعّلة للشركة لكن ممنوعة للمستخدم',
                detail: '${reg.labelAr} (${e.key})'));
          }
        }
      }
      for (final e in company.enabledSecondSystemFeatures.entries) {
        if (e.value == true && !pm.canView(e.key)) {
          final reg = PermissionRegistry.findByKey(e.key);
          if (reg != null) {
            issues.add(_DiagIssue(type: _IssueType.info,
                title: 'ميزة مفعّلة للشركة لكن ممنوعة للمستخدم',
                detail: '${reg.labelAr} (${e.key})'));
          }
        }
      }
    }
    return issues;
  }
}

class _DiagnosticsBody extends StatelessWidget {
  const _DiagnosticsBody();

  @override
  Widget build(BuildContext context) {
    final pm = PermissionManager.instance;
    final auth = VpsAuthService.instance;
    final user = auth.currentUser;
    final company = auth.currentCompany;

    // حساب البيانات
    final firstPerms = pm.firstSystemPermissions;
    final secondPerms = pm.secondSystemPermissions;
    final totalRegistry =
        PermissionRegistry.firstSystem.length + PermissionRegistry.secondSystem.length;
    final grantedFirst =
        firstPerms.values.where((v) => v['view'] == true).length;
    final grantedSecond =
        secondPerms.values.where((v) => v['view'] == true).length;
    final totalGranted = grantedFirst + grantedSecond;
    final totalDenied = totalRegistry - totalGranted;
    final coverage =
        totalRegistry > 0 ? (totalGranted / totalRegistry * 100) : 0.0;

    // المشاكل المحتملة
    final issues = _findIssues(pm, company);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ─── القسم 1: ملخص عام ───
        _buildSectionCard(
          context: context,
          title: 'ملخص عام',
          icon: Icons.dashboard_rounded,
          color: Colors.indigo,
          children: [
            _buildInfoTile(context, 'إجمالي الصلاحيات في Registry',
                '$totalRegistry', Icons.inventory_2_rounded),
            _buildInfoTile(context, 'صلاحيات ممنوحة (view)',
                '$totalGranted', Icons.check_circle_rounded,
                valueColor: Colors.green),
            _buildInfoTile(context, 'صلاحيات محجوبة',
                '$totalDenied', Icons.block_rounded,
                valueColor: Colors.red),
            _buildInfoTile(context, 'نسبة التغطية',
                '${coverage.toStringAsFixed(1)}%', Icons.pie_chart_rounded,
                valueColor: coverage > 70 ? Colors.green : Colors.orange),
            const Divider(),
            _buildInfoTile(context, 'المستخدم', user?.fullName ?? 'غير معروف',
                Icons.person_rounded),
            _buildInfoTile(context, 'الدور', user?.role ?? '-',
                Icons.work_rounded),
            _buildInfoTile(context, 'مدير شركة',
                user?.isAdmin == true ? 'نعم' : 'لا',
                Icons.admin_panel_settings_rounded,
                valueColor: user?.isAdmin == true ? Colors.green : Colors.grey),
          ],
        ),
        const SizedBox(height: 16),

        // ─── القسم 2: خريطة النظام الأول ───
        _buildSystemMapCard(
          context: context,
          title: 'خريطة النظام الأول (الرئيسي)',
          icon: Icons.apps_rounded,
          color: Colors.blue,
          entries: PermissionRegistry.firstSystem,
          permissions: firstPerms,
        ),
        const SizedBox(height: 16),

        // ─── القسم 3: خريطة النظام الثاني (FTTH) ───
        _buildSystemMapCard(
          context: context,
          title: 'خريطة النظام الثاني (FTTH)',
          icon: Icons.cable_rounded,
          color: Colors.teal,
          entries: PermissionRegistry.secondSystem,
          permissions: secondPerms,
        ),
        const SizedBox(height: 16),

        // ─── القسم 4: عناصر بدون حماية ───
        _buildUnprotectedCard(context),
        const SizedBox(height: 16),

        // ─── القسم 5: مشاكل محتملة ───
        _buildIssuesCard(context, issues),
        const SizedBox(height: 32),
      ],
    );
  }

  // ══════════════════════════════════════════
  // القسم 2/3: خريطة النظام
  // ══════════════════════════════════════════

  Widget _buildSystemMapCard({
    required BuildContext context,
    required String title,
    required IconData icon,
    required Color color,
    required List<PermissionEntry> entries,
    required Map<String, Map<String, bool>> permissions,
  }) {
    final grouped = PermissionRegistry.getGrouped(entries);
    final actions = ['view', 'add', 'edit', 'delete', 'export', 'import', 'print', 'send'];
    final actionLabels = {
      'view': 'عرض', 'add': 'إضافة', 'edit': 'تعديل', 'delete': 'حذف',
      'export': 'تصدير', 'import': 'استيراد', 'print': 'طباعة', 'send': 'إرسال',
    };

    return _buildSectionCard(
      context: context,
      title: title,
      icon: icon,
      color: color,
      children: [
        // رأس الجدول
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.grey[100],
          child: Row(
            children: [
              const Expanded(flex: 3, child: Text('العنصر',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
              ...actions.map((a) => Expanded(
                child: Center(child: Text(actionLabels[a] ?? a,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10))),
              )),
            ],
          ),
        ),
        const Divider(height: 1),
        // صفوف البيانات
        ...grouped.entries.expand((entry) {
          final parent = entry.key;
          final children = entry.value;
          final parentPerms = permissions[parent.key] ?? {};
          final parentHasView = parentPerms['view'] == true;

          return [
            // صف الأب
            _buildPermRow(
              context: context,
              label: parent.labelAr,
              icon: parent.icon,
              key: parent.key,
              perms: parentPerms,
              actions: actions,
              isParent: true,
              hasIssue: false,
            ),
            // صفوف الأبناء
            ...children.map((child) {
              final childPerms = permissions[child.key] ?? {};
              final childHasView = childPerms['view'] == true;
              // حالة التوارث
              final inherited = !permissions.containsKey(child.key) && parentHasView;
              // تناقض: الأب ممنوع لكن الابن مسموح
              final hasIssue = !parentHasView && childHasView;

              return _buildPermRow(
                context: context,
                label: '  ${child.labelAr}',
                icon: child.icon,
                key: child.key,
                perms: inherited ? parentPerms : childPerms,
                actions: actions,
                isParent: false,
                inherited: inherited,
                hasIssue: hasIssue,
              );
            }),
            const Divider(height: 1),
          ];
        }),
      ],
    );
  }

  Widget _buildPermRow({
    required BuildContext context,
    required String label,
    required IconData icon,
    required String key,
    required Map<String, bool> perms,
    required List<String> actions,
    required bool isParent,
    bool inherited = false,
    bool hasIssue = false,
  }) {
    final bgColor = hasIssue
        ? Colors.red.withValues(alpha: 0.08)
        : inherited
            ? Colors.orange.withValues(alpha: 0.05)
            : null;

    return Container(
      color: bgColor,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Icon(icon, size: 16,
                    color: isParent ? Colors.blueGrey[700] : Colors.blueGrey[400]),
                const SizedBox(width: 4),
                Expanded(
                  child: Tooltip(
                    message: key,
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: isParent ? 13 : 12,
                        fontWeight: isParent ? FontWeight.bold : FontWeight.normal,
                        color: isParent ? Colors.black87 : Colors.black54,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                if (inherited)
                  Tooltip(
                    message: 'وارث من الأب',
                    child: Icon(Icons.subdirectory_arrow_left_rounded,
                        size: 14, color: Colors.orange[700]),
                  ),
                if (hasIssue)
                  Tooltip(
                    message: 'تناقض: الأب ممنوع لكن الابن مسموح',
                    child: Icon(Icons.warning_rounded,
                        size: 14, color: Colors.red[700]),
                  ),
              ],
            ),
          ),
          ...actions.map((a) {
            final allowed = perms[a] == true;
            final registryEntry = PermissionRegistry.findByKey(key);
            final isApplicable = registryEntry?.allowedActions == null ||
                registryEntry!.allowedActions!.contains(a);

            return Expanded(
              child: Center(
                child: isApplicable
                    ? Icon(
                        allowed ? Icons.check_circle_rounded : Icons.cancel_rounded,
                        size: 16,
                        color: allowed ? Colors.green : Colors.red[300],
                      )
                    : Icon(Icons.remove_rounded, size: 14, color: Colors.grey[300]),
              ),
            );
          }),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════
  // القسم 4: عناصر بدون حماية
  // ══════════════════════════════════════════

  Widget _buildUnprotectedCard(BuildContext context) {
    final items = <_UnprotectedItem>[
      // ─── النظام الأول ───
      _UnprotectedItem(
        name: 'إعدادات الشركة (القائمة الجانبية)',
        system: 'النظام الأول',
        severity: _Severity.low,
        reason: 'محمية ضمنياً — تظهر فقط للمدير',
      ),

      // ─── المحاسبة (محمية ضمنياً عبر accounting) ───
      _UnprotectedItem(
        name: 'ميزان المراجعة',
        system: 'المحاسبة',
        severity: _Severity.low,
        reason: 'محمي ضمنياً عبر صلاحية accounting',
      ),
      _UnprotectedItem(
        name: 'قائمة الدخل',
        system: 'المحاسبة',
        severity: _Severity.low,
        reason: 'محمي ضمنياً عبر صلاحية accounting',
      ),
      _UnprotectedItem(
        name: 'الميزانية العمومية',
        system: 'المحاسبة',
        severity: _Severity.low,
        reason: 'محمي ضمنياً عبر صلاحية accounting',
      ),
      _UnprotectedItem(
        name: 'التدفقات النقدية',
        system: 'المحاسبة',
        severity: _Severity.low,
        reason: 'محمي ضمنياً عبر صلاحية accounting',
      ),
      _UnprotectedItem(
        name: 'أعمار الديون',
        system: 'المحاسبة',
        severity: _Severity.low,
        reason: 'محمي ضمنياً عبر صلاحية accounting',
      ),
      _UnprotectedItem(
        name: 'المقارنة الشهرية',
        system: 'المحاسبة',
        severity: _Severity.low,
        reason: 'محمي ضمنياً عبر صلاحية accounting',
      ),
      _UnprotectedItem(
        name: 'الميزانية التقديرية',
        system: 'المحاسبة',
        severity: _Severity.low,
        reason: 'محمي ضمنياً عبر صلاحية accounting',
      ),
      _UnprotectedItem(
        name: 'النسب المالية',
        system: 'المحاسبة',
        severity: _Severity.low,
        reason: 'محمي ضمنياً عبر صلاحية accounting',
      ),
      _UnprotectedItem(
        name: 'المقارنة السنوية',
        system: 'المحاسبة',
        severity: _Severity.low,
        reason: 'محمي ضمنياً عبر صلاحية accounting',
      ),

      // ─── FTTH ───
      _UnprotectedItem(
        name: 'قوالب الرسائل',
        system: 'FTTH',
        severity: _Severity.low,
        reason: 'محمية ضمنياً — تظهر داخل صفحة FTTH المحمية',
      ),
      _UnprotectedItem(
        name: 'إعدادات الواتساب المحلية',
        system: 'FTTH',
        severity: _Severity.low,
        reason: 'محمية ضمنياً — تظهر داخل صفحة FTTH المحمية',
      ),
    ];

    final highSeverity = items.where((i) => i.severity == _Severity.high).toList();
    final mediumSeverity = items.where((i) => i.severity == _Severity.medium).toList();
    final lowSeverity = items.where((i) => i.severity == _Severity.low).toList();

    return _buildSectionCard(
      context: context,
      title: 'عناصر بدون حماية صلاحيات مباشرة',
      icon: Icons.shield_outlined,
      color: Colors.orange,
      children: [
        if (highSeverity.isNotEmpty) ...[
          _buildSeverityHeader('خطورة عالية — بدون أي حماية', Colors.red),
          ...highSeverity.map((i) => _buildUnprotectedRow(i)),
          const Divider(),
        ],
        if (mediumSeverity.isNotEmpty) ...[
          _buildSeverityHeader('خطورة متوسطة', Colors.orange),
          ...mediumSeverity.map((i) => _buildUnprotectedRow(i)),
          const Divider(),
        ],
        _buildSeverityHeader(
            'خطورة منخفضة — محمية ضمنياً (${lowSeverity.length})',
            Colors.green),
        ...lowSeverity.map((i) => _buildUnprotectedRow(i)),
      ],
    );
  }

  Widget _buildSeverityHeader(String text, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: color.withValues(alpha: 0.1),
      child: Text(text,
          style: TextStyle(
              fontWeight: FontWeight.bold, fontSize: 12, color: color)),
    );
  }

  Widget _buildUnprotectedRow(_UnprotectedItem item) {
    final severityColor = switch (item.severity) {
      _Severity.high => Colors.red,
      _Severity.medium => Colors.orange,
      _Severity.low => Colors.green,
    };

    return ListTile(
      dense: true,
      leading: Icon(
        switch (item.severity) {
          _Severity.high => Icons.error_rounded,
          _Severity.medium => Icons.warning_rounded,
          _Severity.low => Icons.info_rounded,
        },
        color: severityColor,
        size: 20,
      ),
      title: Text(item.name, style: const TextStyle(fontSize: 13)),
      subtitle: Text(item.reason,
          style: TextStyle(fontSize: 11, color: Colors.grey[600])),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: severityColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(item.system,
            style: TextStyle(fontSize: 10, color: severityColor)),
      ),
    );
  }

  // ══════════════════════════════════════════
  // القسم 5: مشاكل محتملة
  // ══════════════════════════════════════════

  List<_DiagIssue> _findIssues(
      PermissionManager pm, VpsCompanyInfo? company) {
    final issues = <_DiagIssue>[];
    final firstPerms = pm.firstSystemPermissions;
    final secondPerms = pm.secondSystemPermissions;

    // 1. صلاحيات مسجلة في Registry لكن غير موجودة في بيانات المستخدم
    for (final entry in PermissionRegistry.firstSystem) {
      if (entry.isTopLevel && !firstPerms.containsKey(entry.key)) {
        issues.add(_DiagIssue(
          type: _IssueType.warning,
          title: 'صلاحية مسجلة غير موجودة في بيانات المستخدم',
          detail: '${entry.labelAr} (${entry.key}) — النظام الأول\n'
              'ستُعتبر ممنوعة (جميع الإجراءات = false)',
        ));
      }
    }
    for (final entry in PermissionRegistry.secondSystem) {
      if (!secondPerms.containsKey(entry.key)) {
        issues.add(_DiagIssue(
          type: _IssueType.warning,
          title: 'صلاحية مسجلة غير موجودة في بيانات المستخدم',
          detail: '${entry.labelAr} (${entry.key}) — النظام الثاني\n'
              'ستُعتبر ممنوعة (جميع الإجراءات = false)',
        ));
      }
    }

    // 2. صلاحيات في بيانات المستخدم غير مسجلة في Registry
    for (final key in firstPerms.keys) {
      if (PermissionRegistry.findByKey(key) == null) {
        issues.add(_DiagIssue(
          type: _IssueType.warning,
          title: 'صلاحية غير معروفة في بيانات المستخدم',
          detail: '$key — موجود في بيانات النظام الأول لكن غير مسجل في Registry',
        ));
      }
    }
    for (final key in secondPerms.keys) {
      if (PermissionRegistry.findByKey(key) == null) {
        issues.add(_DiagIssue(
          type: _IssueType.warning,
          title: 'صلاحية غير معروفة في بيانات المستخدم',
          detail: '$key — موجود في بيانات النظام الثاني لكن غير مسجل في Registry',
        ));
      }
    }

    // 3. تناقضات هرمية: أب ممنوع لكن ابن مسموح
    for (final entry in PermissionRegistry.firstSystem) {
      if (entry.parent != null) {
        final parentPerms = firstPerms[entry.parent!];
        final childPerms = firstPerms[entry.key];
        if (parentPerms != null &&
            parentPerms['view'] != true &&
            childPerms != null &&
            childPerms['view'] == true) {
          issues.add(_DiagIssue(
            type: _IssueType.error,
            title: 'تناقض هرمي',
            detail:
                '${entry.labelAr} (${entry.key}) مسموح view\n'
                'لكن الأب (${entry.parent}) ممنوع view\n'
                'النتيجة: الابن سيُحجب لأن الأب مغلق',
          ));
        }
      }
    }

    // 4. ميزات شركة مفعّلة لكن المستخدم ممنوع
    if (company != null) {
      for (final entry in company.enabledFirstSystemFeatures.entries) {
        if (entry.value == true && !pm.canView(entry.key)) {
          final regEntry = PermissionRegistry.findByKey(entry.key);
          if (regEntry != null) {
            issues.add(_DiagIssue(
              type: _IssueType.info,
              title: 'ميزة مفعّلة للشركة لكن ممنوعة للمستخدم',
              detail:
                  '${regEntry.labelAr} (${entry.key}) — مفعّلة على مستوى الشركة\n'
                  'لكن المستخدم الحالي لا يملك صلاحية view',
            ));
          }
        }
      }
      for (final entry in company.enabledSecondSystemFeatures.entries) {
        if (entry.value == true && !pm.canView(entry.key)) {
          final regEntry = PermissionRegistry.findByKey(entry.key);
          if (regEntry != null) {
            issues.add(_DiagIssue(
              type: _IssueType.info,
              title: 'ميزة مفعّلة للشركة لكن ممنوعة للمستخدم',
              detail:
                  '${regEntry.labelAr} (${entry.key}) — مفعّلة على مستوى الشركة\n'
                  'لكن المستخدم الحالي لا يملك صلاحية view',
            ));
          }
        }
      }
    }

    return issues;
  }

  Widget _buildIssuesCard(BuildContext context, List<_DiagIssue> issues) {
    final errors = issues.where((i) => i.type == _IssueType.error).toList();
    final warnings = issues.where((i) => i.type == _IssueType.warning).toList();
    final infos = issues.where((i) => i.type == _IssueType.info).toList();

    return _buildSectionCard(
      context: context,
      title: 'مشاكل محتملة (${issues.length})',
      icon: Icons.bug_report_rounded,
      color: issues.isEmpty
          ? Colors.green
          : errors.isNotEmpty
              ? Colors.red
              : Colors.orange,
      children: [
        if (issues.isEmpty)
          const ListTile(
            leading: Icon(Icons.check_circle_rounded, color: Colors.green, size: 32),
            title: Text('لا توجد مشاكل'),
            subtitle: Text('جميع الصلاحيات متسقة ومتوافقة'),
          )
        else ...[
          if (errors.isNotEmpty) ...[
            _buildSeverityHeader('أخطاء (${errors.length})', Colors.red),
            ...errors.map((i) => _buildIssueRow(i)),
          ],
          if (warnings.isNotEmpty) ...[
            _buildSeverityHeader('تحذيرات (${warnings.length})', Colors.orange),
            ...warnings.map((i) => _buildIssueRow(i)),
          ],
          if (infos.isNotEmpty) ...[
            _buildSeverityHeader('معلومات (${infos.length})', Colors.blue),
            ...infos.map((i) => _buildIssueRow(i)),
          ],
        ],
      ],
    );
  }

  Widget _buildIssueRow(_DiagIssue issue) {
    final (iconData, color) = switch (issue.type) {
      _IssueType.error => (Icons.error_rounded, Colors.red),
      _IssueType.warning => (Icons.warning_rounded, Colors.orange),
      _IssueType.info => (Icons.info_rounded, Colors.blue),
    };

    return ExpansionTile(
      leading: Icon(iconData, color: color, size: 20),
      title: Text(issue.title,
          style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w600)),
      childrenPadding: const EdgeInsets.only(right: 56, left: 16, bottom: 8),
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: SelectableText(issue.detail,
              style: const TextStyle(fontSize: 12, height: 1.5)),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════
  // UI Helpers (نفس نمط CompanyDiagnosticsPage)
  // ══════════════════════════════════════════

  Widget _buildSectionCard({
    required BuildContext context,
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.cairo(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoTile(BuildContext context, String label, String value,
      IconData icon, {Color? valueColor}) {
    return ListTile(
      leading: Icon(icon, size: 20, color: Colors.grey[600]),
      title:
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
      subtitle: SelectableText(value,
          style: TextStyle(color: valueColor)),
      dense: true,
      trailing: IconButton(
        icon: const Icon(Icons.copy, size: 18),
        onPressed: () {
          Clipboard.setData(ClipboardData(text: '$label: $value'));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('تم نسخ: $label'),
                duration: const Duration(seconds: 1)),
          );
        },
        tooltip: 'نسخ',
      ),
    );
  }
}

// ══════════════════════════════════════════
// نماذج البيانات
// ══════════════════════════════════════════

enum _Severity { high, medium, low }

class _UnprotectedItem {
  final String name;
  final String system;
  final _Severity severity;
  final String reason;

  const _UnprotectedItem({
    required this.name,
    required this.system,
    required this.severity,
    required this.reason,
  });
}

enum _IssueType { error, warning, info }

class _DiagIssue {
  final _IssueType type;
  final String title;
  final String detail;

  const _DiagIssue({
    required this.type,
    required this.title,
    required this.detail,
  });
}
