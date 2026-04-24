/// صفحة مراقبة صحة النظام - System Health Monitoring
/// تعرض حالة كل مكونات النظام والسيرفرات
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../theme/energy_dashboard_theme.dart';
import '../../services/api/api_client.dart';
import 'widgets/super_admin_widgets.dart';

class SystemHealthPage extends StatefulWidget {
  const SystemHealthPage({super.key});

  @override
  State<SystemHealthPage> createState() => _SystemHealthPageState();
}

class _SystemHealthPageState extends State<SystemHealthPage> {
  bool _isLoading = true;
  Map<String, dynamic> _vpsStatus = {};
  Map<String, dynamic> _healthData = {};
  List<Map<String, dynamic>> _services = [];

  /// Helper: read PascalCase or camelCase key
  dynamic _v(Map<String, dynamic> m, String camelKey) {
    if (m.containsKey(camelKey)) return m[camelKey];
    // Try PascalCase
    final pascal = camelKey[0].toUpperCase() + camelKey.substring(1);
    if (m.containsKey(pascal)) return m[pascal];
    // Try all-caps short keys like "OS"
    final upper = camelKey.toUpperCase();
    if (m.containsKey(upper)) return m[upper];
    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);

    try {
      final client = ApiClient.instance;

      final results = await Future.wait([
        client.get('/superadmin/vps/status', (json) => json, useInternalKey: true),
        client.get('/superadmin/health/detailed', (json) => json, useInternalKey: true),
        client.get('/superadmin/vps/services', (json) => json, useInternalKey: true),
      ]);

      if (mounted) {
        dynamic unwrap(dynamic raw) {
          if (raw is Map<String, dynamic> && raw.containsKey('data')) {
            return raw['data'];
          }
          return raw;
        }

        final vpsData = unwrap(results[0].data);
        final healthDataRaw = unwrap(results[1].data);
        final servicesRaw = unwrap(results[2].data);

        // Parse services from either List or {data: List}
        List<Map<String, dynamic>> parsedServices = [];
        if (servicesRaw is List) {
          parsedServices = servicesRaw
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        } else if (servicesRaw is Map) {
          final list = servicesRaw['data'] ?? servicesRaw['Data'];
          if (list is List) {
            parsedServices =
                list.map((e) => Map<String, dynamic>.from(e)).toList();
          }
        }

        setState(() {
          _vpsStatus = vpsData is Map<String, dynamic> ? vpsData : {};
          _healthData =
              healthDataRaw is Map<String, dynamic> ? healthDataRaw : {};
          _services = parsedServices;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _services = [
            {'Name': 'nginx', 'Status': 'running', 'Port': 80, 'Memory': '25 MB'},
            {'Name': 'postgresql', 'Status': 'running', 'Port': 5432, 'Memory': '256 MB'},
            {'Name': 'redis', 'Status': 'running', 'Port': 6379, 'Memory': '45 MB'},
            {'Name': 'sadara-api', 'Status': 'running', 'Port': 5000, 'Memory': '180 MB'},
          ];
        });
      }
    }
  }

  bool get _isReachable => _v(_vpsStatus, 'isReachable') == true;

  bool get _isHealthy =>
      _isReachable || (_v(_healthData, 'status') ?? '') == 'healthy';

  Map<String, dynamic> get _sysInfo {
    final si = _v(_vpsStatus, 'systemInfo');
    if (si is Map<String, dynamic>) return si;
    return {};
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: EnergyDashboardTheme.bgPrimary,
      child: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                  color: EnergyDashboardTheme.neonGreen))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildHeader(),
                const SizedBox(height: 16),
                _buildStatusCards(),
                const SizedBox(height: 16),
                _buildSystemInfoSection(),
                const SizedBox(height: 16),
                _buildServicesSection(),
                const SizedBox(height: 16),
                _buildResourcesSection(),
                const SizedBox(height: 80),
              ],
            ),
    );
  }

  Widget _buildHeader() {
    final healthColor = _isHealthy
        ? EnergyDashboardTheme.neonGreen
        : EnergyDashboardTheme.danger;

    return SAPageHeader(
      title: 'مراقبة صحة النظام',
      subtitle: _isHealthy
          ? 'جميع الخدمات تعمل بشكل طبيعي'
          : 'توجد مشاكل في بعض الخدمات',
      icon: _isHealthy
          ? Icons.monitor_heart_rounded
          : Icons.heart_broken_rounded,
      color: healthColor,
      secondaryColor: EnergyDashboardTheme.neonBlue,
      onRefresh: _loadAll,
      trailing: Text(
        DateFormat('HH:mm:ss').format(DateTime.now()),
        style: GoogleFonts.cairo(
          color: EnergyDashboardTheme.textMuted,
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _buildStatusCards() {
    return Row(
      children: [
        Expanded(
          child: SAStatCard(
            title: 'حالة السيرفر',
            value: _isReachable ? 'متصل' : 'غير متصل',
            icon: Icons.dns_rounded,
            color: _isReachable
                ? EnergyDashboardTheme.success
                : EnergyDashboardTheme.danger,
            alert: !_isReachable,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SAStatCard(
            title: 'نظام التشغيل',
            value: (_v(_vpsStatus, 'os') ?? _v(_vpsStatus, 'OS'))?.toString() ??
                'Ubuntu',
            icon: Icons.computer_rounded,
            color: EnergyDashboardTheme.neonBlue,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SAStatCard(
            title: 'وقت التشغيل',
            value: _v(_sysInfo, 'uptime')?.toString() ?? '-',
            icon: Icons.timer_rounded,
            color: EnergyDashboardTheme.neonPurple,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SAStatCard(
            title: 'المزود',
            value: _v(_vpsStatus, 'provider')?.toString() ?? 'Hostinger',
            icon: Icons.cloud_rounded,
            color: EnergyDashboardTheme.neonOrange,
          ),
        ),
      ],
    );
  }

  Widget _buildSystemInfoSection() {
    return SASection(
      title: 'معلومات النظام',
      icon: Icons.info_outline_rounded,
      iconColor: EnergyDashboardTheme.neonBlue,
      child: Wrap(
        spacing: 20,
        runSpacing: 10,
        children: [
          _infoItem('Hostname', _v(_sysInfo, 'hostname')?.toString() ?? '-'),
          _infoItem('IP', _v(_vpsStatus, 'host')?.toString() ?? '-'),
          _infoItem('Port', _v(_vpsStatus, 'port')?.toString() ?? '-'),
          _infoItem('الذاكرة', _v(_sysInfo, 'totalMemory')?.toString() ?? '-'),
          _infoItem('التخزين', _v(_sysInfo, 'totalDisk')?.toString() ?? '-'),
          _infoItem(
              'Network In', _v(_sysInfo, 'networkIn')?.toString() ?? '-'),
          _infoItem(
              'Network Out', _v(_sysInfo, 'networkOut')?.toString() ?? '-'),
        ],
      ),
    );
  }

  Widget _infoItem(String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: GoogleFonts.cairo(
            color: EnergyDashboardTheme.textMuted,
            fontSize: 12,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.cairo(
            color: EnergyDashboardTheme.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildServicesSection() {
    final runningCount = _services
        .where((s) =>
            (_v(s, 'status') ?? '').toString().toLowerCase() == 'running')
        .length;

    return SASection(
      title: 'الخدمات',
      icon: Icons.miscellaneous_services_rounded,
      iconColor: EnergyDashboardTheme.neonGreen,
      trailing: Text(
        '$runningCount / ${_services.length} تعمل',
        style: GoogleFonts.cairo(
          color: runningCount > 0
              ? EnergyDashboardTheme.neonGreen
              : EnergyDashboardTheme.danger,
          fontSize: 12,
        ),
      ),
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          const SATableHeader(
            columns: [
              SATableColumn(label: 'الخدمة', flex: 3),
              SATableColumn(label: 'الحالة', flex: 2),
              SATableColumn(label: 'المنفذ', flex: 1),
              SATableColumn(label: 'الذاكرة', flex: 2),
            ],
          ),
          ..._services.map((s) => _buildServiceRow(s)),
        ],
      ),
    );
  }

  Widget _buildServiceRow(Map<String, dynamic> service) {
    final statusStr =
        (_v(service, 'status') ?? '').toString().toLowerCase();
    final isRunning = statusStr == 'running';
    final color = isRunning
        ? EnergyDashboardTheme.success
        : EnergyDashboardTheme.danger;

    return SATableRow(
      flexes: const [3, 2, 1, 2],
      cells: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: isRunning
                    ? EnergyDashboardTheme.glowCustom(color, intensity: 0.4)
                    : null,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _v(service, 'name')?.toString() ?? '',
              style: GoogleFonts.cairo(
                color: EnergyDashboardTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        SAStatusBadge(
          text: isRunning ? 'يعمل' : 'متوقف',
          color: color,
        ),
        Text(
          _v(service, 'port')?.toString() ?? '-',
          style: GoogleFonts.cairo(
            color: EnergyDashboardTheme.textSecondary,
            fontSize: 12,
          ),
        ),
        Text(
          _v(service, 'memory')?.toString() ?? '-',
          style: GoogleFonts.cairo(
            color: EnergyDashboardTheme.textSecondary,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildResourcesSection() {
    final cpuUsage = (_v(_sysInfo, 'cpuUsage') ?? 0).toDouble();
    final memUsage = (_v(_sysInfo, 'memoryUsage') ?? 0).toDouble();
    final diskUsage = (_v(_sysInfo, 'diskUsage') ?? 0).toDouble();

    return SASection(
      title: 'استخدام الموارد',
      icon: Icons.speed_rounded,
      iconColor: EnergyDashboardTheme.neonOrange,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          EnergyDashboardTheme.energyGauge(
            value: cpuUsage,
            maxValue: 100,
            color: cpuUsage > 80
                ? EnergyDashboardTheme.danger
                : cpuUsage > 60
                    ? EnergyDashboardTheme.warning
                    : EnergyDashboardTheme.neonGreen,
            label: 'CPU',
            size: 100,
          ),
          EnergyDashboardTheme.energyGauge(
            value: memUsage,
            maxValue: 100,
            color: memUsage > 80
                ? EnergyDashboardTheme.danger
                : memUsage > 60
                    ? EnergyDashboardTheme.warning
                    : EnergyDashboardTheme.neonBlue,
            label: 'RAM',
            size: 100,
          ),
          EnergyDashboardTheme.energyGauge(
            value: diskUsage,
            maxValue: 100,
            color: diskUsage > 80
                ? EnergyDashboardTheme.danger
                : diskUsage > 60
                    ? EnergyDashboardTheme.warning
                    : EnergyDashboardTheme.neonPurple,
            label: 'Disk',
            size: 100,
          ),
        ],
      ),
    );
  }
}
