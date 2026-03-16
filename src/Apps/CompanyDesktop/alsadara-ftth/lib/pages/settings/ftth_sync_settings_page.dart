import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../services/custom_auth_service.dart';
import '../../services/vps_auth_service.dart';
import '../../services/ftth_settings_service.dart';
import '../../services/vps_sync_service.dart';

class FtthSyncSettingsPage extends StatefulWidget {
  const FtthSyncSettingsPage({super.key});

  @override
  State<FtthSyncSettingsPage> createState() => _FtthSyncSettingsPageState();
}

class _FtthSyncSettingsPageState extends State<FtthSyncSettingsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  bool _loading = true;
  bool _saving = false;
  bool _testing = false;
  bool _syncing = false;

  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscurePassword = true;
  int _syncInterval = 60;
  bool _autoSync = true;
  int _syncStartHour = 6;
  int _syncEndHour = 23;

  DateTime? _lastSyncAt;
  String? _lastSyncError;
  int _subscriberCount = 0;
  bool _isSyncInProgress = false;
  int _consecutiveFailures = 0;

  List<Map<String, dynamic>> _syncLogs = [];
  bool _logsLoading = false;

  // إحصائيات البيانات الناقصة
  Map<String, dynamic>? _missingStats;
  bool _refetching = false;

  // حماية من إعادة عرض "قيد التنفيذ" بعد الإلغاء مباشرة
  DateTime? _cancelledAt;

  String? get _companyId =>
      CustomAuthService().currentTenantId ??
      VpsAuthService.instance.currentCompanyId;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _loadSettings();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    if (_companyId == null) return;
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        FtthSettingsService.getSettings(_companyId!),
        FtthSettingsService.getSyncStatus(_companyId!),
      ]);
      final settings = results[0];
      final status = results[1];
      if (!mounted) return;
      setState(() {
        if (settings != null && settings['exists'] == true) {
          _usernameCtrl.text = settings['ftthUsername'] ?? '';
          _passwordCtrl.text = settings['ftthPassword'] ?? '';
          _syncInterval = settings['syncIntervalMinutes'] ?? 60;
          _autoSync = settings['isAutoSyncEnabled'] ?? true;
          _syncStartHour = settings['syncStartHour'] ?? 6;
          _syncEndHour = settings['syncEndHour'] ?? 23;
        }
        if (status != null && status['configured'] == true) {
          _lastSyncAt = status['lastSyncAt'] != null
              ? DateTime.tryParse(status['lastSyncAt'])
              : null;
          _lastSyncError = status['lastSyncError'];
          _subscriberCount = status['currentDbCount'] ?? 0;
          // بعد الإلغاء مباشرة: لا نعيد isSyncInProgress=true من السيرفر لمدة 15 ثانية
          // لأن الخدمة تحتاج وقت لتتوقف فعلياً
          final serverSyncInProgress = status['isSyncInProgress'] ?? false;
          final justCancelled = _cancelledAt != null &&
              DateTime.now().difference(_cancelledAt!).inSeconds < 15;
          if (justCancelled && serverSyncInProgress) {
            // تجاهل — الإلغاء قيد الانتظار
          } else {
            _isSyncInProgress = serverSyncInProgress;
            if (!serverSyncInProgress)
              _cancelledAt = null; // انتهت فترة الحماية
          }
          _consecutiveFailures = status['consecutiveFailures'] ?? 0;
        }
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
    _loadLogs();
    _loadMissingStats();
  }

  Future<void> _loadMissingStats() async {
    if (_companyId == null) return;
    final stats = await FtthSettingsService.getMissingStats(_companyId!);
    if (mounted) setState(() => _missingStats = stats);
  }

  Future<void> _loadLogs() async {
    if (_companyId == null) return;
    setState(() => _logsLoading = true);
    final logs = await FtthSettingsService.getSyncLogs(_companyId!);
    if (mounted)
      setState(() {
        _syncLogs = logs;
        _logsLoading = false;
      });
  }

  Future<void> _save() async {
    if (_companyId == null) return;
    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text.trim();
    if (username.isEmpty) {
      _showSnack('يجب إدخال اسم المستخدم', isError: true);
      return;
    }
    if (password.isEmpty) {
      _showSnack('يجب إدخال كلمة المرور', isError: true);
      return;
    }

    setState(() => _saving = true);
    final ok = await FtthSettingsService.saveSettings(
      companyId: _companyId!,
      ftthUsername: username,
      ftthPassword: password,
      syncIntervalMinutes: _syncInterval,
      isAutoSyncEnabled: _autoSync,
      syncStartHour: _syncStartHour,
      syncEndHour: _syncEndHour,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    _showSnack(ok ? 'تم حفظ الإعدادات بنجاح' : 'فشل حفظ الإعدادات',
        isError: !ok);
  }

  Future<void> _testConnection() async {
    if (_companyId == null) return;
    setState(() => _testing = true);
    final result = await FtthSettingsService.testConnection(_companyId!);
    if (!mounted) return;
    setState(() => _testing = false);
    if (result['success'] == true) {
      _showSnack('الاتصال ناجح — ${result['totalSubscribers'] ?? 0} مشترك');
    } else {
      _showSnack('فشل الاتصال', isError: true);
    }
  }

  Future<void> _triggerSync() async {
    if (_companyId == null) return;
    setState(() => _syncing = true);
    final ok = await FtthSettingsService.triggerSync(_companyId!);
    if (!mounted) return;
    setState(() => _syncing = false);
    _showSnack(ok ? 'بدأت المزامنة الآن' : 'فشل تشغيل المزامنة', isError: !ok);
    if (ok)
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) _loadSettings();
      });
  }

  Future<void> _cancelSync() async {
    if (_companyId == null) return;
    final ok = await FtthSettingsService.cancelSync(_companyId!);
    if (!mounted) return;
    if (ok) {
      setState(() {
        _isSyncInProgress = false;
        _cancelledAt = DateTime.now();
      });
      _showSnack('تم إرسال طلب الإلغاء — قد يستغرق بضع ثوان');
      // إعادة تحميل الحالة بعد 10 ثوان (لإعطاء الخدمة وقت كافٍ للتوقف)
      Future.delayed(const Duration(seconds: 10), () {
        if (mounted) _loadSettings();
      });
    } else {
      _showSnack('لا توجد مزامنة قيد التنفيذ', isError: true);
    }
  }

  Future<void> _refetchMissing() async {
    if (_companyId == null) return;
    setState(() => _refetching = true);
    final result = await FtthSettingsService.refetchMissing(_companyId!);
    if (!mounted) return;
    setState(() => _refetching = false);
    if (result != null && result['success'] == true) {
      final msg = result['message'] ?? 'بدأت المزامنة';
      _showSnack(msg);
      setState(() => _isSyncInProgress = true);
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          _loadSettings();
          _loadMissingStats();
        }
      });
    } else {
      _showSnack('فشل إعادة جلب البيانات الناقصة', isError: true);
    }
  }

  Future<void> _deleteLog(String logId) async {
    if (_companyId == null || logId.isEmpty) return;
    final ok = await FtthSettingsService.deleteSyncLog(_companyId!, logId);
    if (!mounted) return;
    if (ok) {
      setState(
          () => _syncLogs.removeWhere((l) => l['id']?.toString() == logId));
    } else {
      _showSnack('فشل حذف السجل', isError: true);
    }
  }

  Future<void> _deleteAllLogs() async {
    if (_companyId == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('حذف كل السجلات', style: TextStyle(fontSize: 14)),
          content: const Text('هل أنت متأكد من حذف كل سجلات المزامنة؟',
              style: TextStyle(fontSize: 13)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('حذف الكل')),
          ],
        ),
      ),
    );
    if (confirm != true || !mounted) return;
    final ok = await FtthSettingsService.deleteAllSyncLogs(_companyId!);
    if (!mounted) return;
    if (ok) {
      setState(() => _syncLogs.clear());
      _showSnack('تم حذف كل السجلات');
    } else {
      _showSnack('فشل حذف السجلات', isError: true);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, textDirection: TextDirection.rtl),
      backgroundColor: isError ? Colors.red.shade600 : Colors.green.shade600,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: AppBar(
          title: const Text('مزامنة FTTH',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 0.5,
          toolbarHeight: 42,
          bottom: TabBar(
            controller: _tabCtrl,
            labelColor: Colors.deepPurple,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.deepPurple,
            labelStyle:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            tabs: const [
              Tab(text: 'الإعدادات', height: 36),
              Tab(text: 'سجل المزامنات', height: 36),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                controller: _tabCtrl,
                children: [_buildSettingsTab(), _buildLogsTab()],
              ),
      ),
    );
  }

  // ═══════════════════════════════════════
  // تاب الإعدادات
  // ═══════════════════════════════════════

  Widget _buildSettingsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildCredentialsCard()),
            const SizedBox(width: 10),
            Expanded(child: _buildSyncSettingsCard()),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildSyncStatusCard()),
            const SizedBox(width: 10),
            Expanded(child: _buildVpsDownloadCard()),
          ],
        ),
        const SizedBox(height: 10),
        _buildMissingDataCard(),
        const SizedBox(height: 10),
        _buildSaveButton(),
        const SizedBox(height: 8),
      ]),
    );
  }

  Widget _buildCredentialsCard() {
    return Card(
      color: Colors.white,
      elevation: 0.5,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.key_rounded,
                size: 18, color: Colors.deepPurple.shade400),
            const SizedBox(width: 6),
            const Text('بيانات الدخول',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          ]),
          const Divider(height: 16),
          _compactField(_usernameCtrl, 'يوزر FTTH', Icons.person_outline),
          const SizedBox(height: 10),
          _compactField(
            _passwordCtrl,
            'الباسوورد',
            Icons.lock_outline,
            obscure: _obscurePassword,
            suffixIcon: IconButton(
              icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  size: 20),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 36,
            child: OutlinedButton.icon(
              onPressed: _testing ? null : _testConnection,
              icon: _testing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.wifi_tethering_rounded, size: 18),
              label: Text(_testing ? 'جاري...' : 'اختبار الاتصال',
                  style: const TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.deepPurple,
                side: BorderSide(color: Colors.deepPurple.shade200),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _compactField(TextEditingController ctrl, String label, IconData icon,
      {bool obscure = false, Widget? suffixIcon}) {
    return SizedBox(
      height: 42,
      child: TextField(
        controller: ctrl,
        obscureText: obscure,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 12),
          prefixIcon: Icon(icon, size: 18),
          suffixIcon: suffixIcon,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          filled: true,
          fillColor: Colors.grey.shade50,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
        ),
      ),
    );
  }

  Widget _buildSyncSettingsCard() {
    return Card(
      color: Colors.white,
      elevation: 0.5,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.sync_rounded, size: 18, color: Colors.blue.shade400),
            const SizedBox(width: 6),
            const Text('إعدادات المزامنة',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          ]),
          const Divider(height: 16),
          SwitchListTile(
            title: const Text('المزامنة التلقائية',
                style: TextStyle(fontSize: 13)),
            subtitle: const Text('مزامنة تلقائية من FTTH',
                style: TextStyle(fontSize: 11)),
            value: _autoSync,
            onChanged: (v) => setState(() => _autoSync = v),
            activeColor: Colors.deepPurple,
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
          const SizedBox(height: 4),
          Row(children: [
            const Text('الفاصل:', style: TextStyle(fontSize: 12)),
            const SizedBox(width: 8),
            Expanded(
                child: _compactDropdown<int>(
              value: _syncInterval,
              items: const {
                30: '30 دقيقة',
                60: 'ساعة',
                120: 'ساعتان',
                360: '6 ساعات',
                720: '12 ساعة',
                1440: '24 ساعة'
              },
              onChanged: (v) {
                if (v != null) setState(() => _syncInterval = v);
              },
            )),
          ]),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade100),
            ),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.schedule_rounded,
                    size: 16, color: Colors.blue.shade600),
                const SizedBox(width: 4),
                Text('الساعات النشطة',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.blue.shade700)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                const Text('من:', style: TextStyle(fontSize: 11)),
                const SizedBox(width: 4),
                Expanded(
                    child: _compactDropdown<int>(
                  value: _syncStartHour,
                  items: {for (var i = 0; i < 24; i++) i: _formatHour(i)},
                  onChanged: (v) {
                    if (v != null) setState(() => _syncStartHour = v);
                  },
                  fillColor: Colors.white,
                )),
                const SizedBox(width: 12),
                const Text('إلى:', style: TextStyle(fontSize: 11)),
                const SizedBox(width: 4),
                Expanded(
                    child: _compactDropdown<int>(
                  value: _syncEndHour,
                  items: {for (var i = 0; i < 24; i++) i: _formatHour(i)},
                  onChanged: (v) {
                    if (v != null) setState(() => _syncEndHour = v);
                  },
                  fillColor: Colors.white,
                )),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _compactDropdown<T>({
    required T value,
    required Map<T, String> items,
    required ValueChanged<T?> onChanged,
    Color? fillColor,
  }) {
    return SizedBox(
      height: 36,
      child: DropdownButtonFormField<T>(
        value: value,
        isDense: true,
        items: items.entries
            .map((e) => DropdownMenuItem(
                value: e.key,
                child: Text(e.value, style: const TextStyle(fontSize: 12))))
            .toList(),
        onChanged: onChanged,
        decoration: InputDecoration(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
          filled: true,
          fillColor: fillColor ?? Colors.grey.shade50,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
        ),
      ),
    );
  }

  Widget _buildSyncStatusCard() {
    final hasSync = _lastSyncAt != null;
    final hasError = _lastSyncError != null && _lastSyncError!.isNotEmpty;

    return Card(
      color: Colors.white,
      elevation: 0.5,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.info_outline_rounded,
                size: 18, color: Colors.green.shade400),
            const SizedBox(width: 6),
            const Text('حالة المزامنة',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const Spacer(),
            if (_isSyncInProgress) _badge('قيد التنفيذ', Colors.orange),
          ]),
          const Divider(height: 16),
          _statusRow(
              'آخر مزامنة',
              hasSync
                  ? DateFormat('yyyy/MM/dd HH:mm')
                      .format(_lastSyncAt!.toLocal())
                  : 'لم تتم بعد',
              icon: Icons.access_time,
              color: hasSync ? Colors.green : Colors.grey),
          const SizedBox(height: 6),
          _statusRow(
              'المشتركين', NumberFormat('#,###').format(_subscriberCount),
              icon: Icons.people_outline, color: Colors.blue),
          const SizedBox(height: 6),
          _statusRow(
              'الحالة',
              hasError
                  ? 'خطأ'
                  : hasSync
                      ? 'ناجحة'
                      : 'لم تتم',
              icon: hasError ? Icons.error_outline : Icons.check_circle_outline,
              color: hasError
                  ? Colors.red
                  : hasSync
                      ? Colors.green
                      : Colors.grey),
          if (_consecutiveFailures > 0) ...[
            const SizedBox(height: 6),
            _statusRow('فشل متتالي', '$_consecutiveFailures',
                icon: Icons.warning_amber_rounded, color: Colors.orange),
          ],
          if (hasError) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.red.shade200)),
              child: Text(_lastSyncError!,
                  style: TextStyle(fontSize: 11, color: Colors.red.shade700)),
            ),
          ],
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: SizedBox(
                height: 36,
                child: ElevatedButton.icon(
                  onPressed:
                      _syncing || _isSyncInProgress ? null : _triggerSync,
                  icon: _syncing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.sync_rounded, size: 18),
                  label: Text(_syncing ? 'جاري...' : 'مزامنة الآن',
                      style: const TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade600,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ),
            if (_isSyncInProgress) ...[
              const SizedBox(width: 8),
              SizedBox(
                height: 36,
                child: ElevatedButton.icon(
                  onPressed: _cancelSync,
                  icon: const Icon(Icons.stop_rounded, size: 18),
                  label: const Text('إلغاء', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade600,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ]),
        ]),
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(strokeWidth: 1.5, color: color)),
        const SizedBox(width: 4),
        Text(text,
            style: TextStyle(
                fontSize: 10, color: color, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  String _formatHour(int hour) {
    if (hour == 0) return '12 ص';
    if (hour < 12) return '$hour ص';
    if (hour == 12) return '12 م';
    return '${hour - 12} م';
  }

  Widget _statusRow(String label, String value,
      {required IconData icon, required Color color}) {
    return Row(children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 6),
      Text('$label: ',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      Text(value,
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600, color: color)),
    ]);
  }

  Widget _buildVpsDownloadCard() {
    return ListenableBuilder(
      listenable: VpsSyncService.instance,
      builder: (context, _) {
        final vps = VpsSyncService.instance;
        return Card(
          color: Colors.white,
          elevation: 0.5,
          margin: EdgeInsets.zero,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.cloud_download_rounded,
                    size: 18, color: Colors.teal.shade400),
                const SizedBox(width: 6),
                const Text('تنزيل للجهاز',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                const Spacer(),
                if (vps.isSyncing) _badge('جاري التنزيل', Colors.teal),
              ]),
              const Divider(height: 16),
              // شريط التقدم
              if (vps.isSyncing || vps.progress > 0) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: vps.isSyncing
                        ? (vps.progress > 0 ? vps.progress : null)
                        : vps.progress,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation(
                      vps.lastResult?.success == false
                          ? Colors.red
                          : Colors.teal,
                    ),
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  vps.statusMessage,
                  style: TextStyle(
                    fontSize: 11,
                    color: vps.lastResult?.success == false
                        ? Colors.red.shade600
                        : Colors.teal.shade700,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              // معلومات الكاش المحلي
              FutureBuilder<VpsServerCheck>(
                future: VpsSyncService.checkServerData(),
                builder: (ctx, snap) {
                  if (!snap.hasData) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(children: [
                        SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                                strokeWidth: 1.5, color: Colors.grey.shade400)),
                        const SizedBox(width: 6),
                        Text('جاري فحص السيرفر...',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade500)),
                      ]),
                    );
                  }
                  final check = snap.data!;
                  if (!check.available) {
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(6)),
                      child: Row(children: [
                        Icon(Icons.warning_amber_rounded,
                            size: 16, color: Colors.orange.shade700),
                        const SizedBox(width: 6),
                        Expanded(
                            child: Text(check.error ?? 'لا توجد بيانات',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.orange.shade700))),
                      ]),
                    );
                  }
                  return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _statusRow('السيرفر',
                            NumberFormat('#,###').format(check.serverCount),
                            icon: Icons.cloud_rounded, color: Colors.teal),
                        const SizedBox(height: 4),
                        _statusRow('محلي',
                            NumberFormat('#,###').format(check.localCount),
                            icon: Icons.phone_android_rounded,
                            color: Colors.blue),
                        if (check.hasNewData) ...[
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(4)),
                            child: Text('توجد تحديثات جديدة',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.green.shade700,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ]);
                },
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: SizedBox(
                    height: 36,
                    child: ElevatedButton.icon(
                      onPressed: vps.isSyncing
                          ? null
                          : () => VpsSyncService.instance.syncFromVps(),
                      icon: vps.isSyncing
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.download_rounded, size: 18),
                      label: Text(vps.isSyncing ? 'جاري...' : 'تنزيل',
                          style: const TextStyle(fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 36,
                  child: OutlinedButton.icon(
                    onPressed: vps.isSyncing
                        ? null
                        : () => VpsSyncService.instance.forceFullSync(),
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('كامل', style: TextStyle(fontSize: 11)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.teal,
                      side: BorderSide(color: Colors.teal.shade200),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ]),
            ]),
          ),
        );
      },
    );
  }

  Widget _buildMissingDataCard() {
    final stats = _missingStats;
    final total = stats?['totalSubscribers'] ?? 0;
    final missingFat = stats?['missingFat'] ?? 0;
    final missingFdt = stats?['missingFdt'] ?? 0;
    final missingPhone = stats?['missingPhone'] ?? 0;
    final missingAddress = stats?['missingAddress'] ?? 0;
    final hasMissing = missingFat > 0 || missingPhone > 0 || missingAddress > 0;

    return Card(
      color: Colors.white,
      elevation: 0.5,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.find_replace_rounded,
                size: 18, color: Colors.orange.shade400),
            const SizedBox(width: 6),
            const Text('البيانات الناقصة',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const Spacer(),
            IconButton(
              icon: Icon(Icons.refresh_rounded,
                  size: 18, color: Colors.grey.shade500),
              onPressed: _loadMissingStats,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: 'تحديث',
            ),
          ]),
          const Divider(height: 16),
          if (stats == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                        strokeWidth: 1.5, color: Colors.grey.shade400)),
                const SizedBox(width: 6),
                Text('جاري التحميل...',
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              ]),
            )
          else ...[
            Wrap(spacing: 16, runSpacing: 6, children: [
              _missingChip('الكل', total, Colors.blue),
              _missingChip('بدون FAT', missingFat,
                  missingFat > 0 ? Colors.orange : Colors.green),
              _missingChip('بدون FDT', missingFdt,
                  missingFdt > 0 ? Colors.orange : Colors.green),
              _missingChip('بدون هاتف', missingPhone,
                  missingPhone > 0 ? Colors.orange : Colors.green),
              _missingChip('بدون عنوان', missingAddress,
                  missingAddress > 0 ? Colors.orange : Colors.green),
            ]),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 36,
              child: ElevatedButton.icon(
                onPressed: !hasMissing || _refetching || _isSyncInProgress
                    ? null
                    : _refetchMissing,
                icon: _refetching
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.download_for_offline_rounded, size: 18),
                label: Text(
                  _refetching
                      ? 'جاري...'
                      : hasMissing
                          ? 'جلب البيانات الناقصة'
                          : 'لا توجد بيانات ناقصة',
                  style: const TextStyle(fontSize: 12),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade600,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _missingChip(String label, int count, Color color) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 4),
      Text('$label: ',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
      Text(NumberFormat('#,###').format(count),
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    ]);
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      height: 42,
      child: ElevatedButton.icon(
        onPressed: _saving ? null : _save,
        icon: _saving
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.save_rounded, size: 18),
        label: Text(_saving ? 'جاري الحفظ...' : 'حفظ الإعدادات',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.deepPurple,
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════
  // تاب سجل المزامنات
  // ═══════════════════════════════════════

  Widget _buildLogsTab() {
    if (_logsLoading) return const Center(child: CircularProgressIndicator());
    if (_syncLogs.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.history_rounded, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 8),
          Text('لا توجد عمليات مزامنة بعد',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
        ]),
      );
    }

    return Column(children: [
      // زر حذف الكل
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _deleteAllLogs,
            icon: const Icon(Icons.delete_sweep_rounded, size: 16),
            label: const Text('حذف الكل', style: TextStyle(fontSize: 11)),
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade400),
          ),
        ),
      ),
      Expanded(
        child: RefreshIndicator(
          onRefresh: _loadLogs,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            itemCount: _syncLogs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 4),
            itemBuilder: (ctx, i) => _buildLogItem(_syncLogs[i]),
          ),
        ),
      ),
    ]);
  }

  Widget _buildLogItem(Map<String, dynamic> log) {
    final success = log['success'] == true;
    final startedAt = DateTime.tryParse(log['startedAt'] ?? '');
    final duration = log['durationSeconds'] ?? 0;
    final total = log['subscriberCount'] ?? 0;
    final newSubs = log['newSubscribers'] ?? 0;
    final updated = log['updatedSubscribers'] ?? 0;
    final error = log['errorMessage'];

    return Card(
      color: Colors.white,
      elevation: 0.3,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(
              success ? Icons.check_circle_rounded : Icons.cancel_rounded,
              size: 18,
              color: success ? Colors.green : Colors.red,
            ),
            const SizedBox(width: 6),
            Text(
              startedAt != null
                  ? DateFormat('yyyy/MM/dd — HH:mm').format(startedAt.toLocal())
                  : '—',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: success ? Colors.green.shade50 : Colors.red.shade50,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                success ? 'ناجحة' : 'فشل',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color:
                        success ? Colors.green.shade700 : Colors.red.shade700),
              ),
            ),
            const SizedBox(width: 4),
            InkWell(
              onTap: () => _deleteLog(log['id']?.toString() ?? ''),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(Icons.close_rounded,
                    size: 16, color: Colors.grey.shade400),
              ),
            ),
          ]),
          if (success) ...[
            const SizedBox(height: 6),
            Row(children: [
              _logChip(Icons.people, '$total مشترك', Colors.blue),
              const SizedBox(width: 8),
              if (newSubs > 0) ...[
                _logChip(Icons.person_add, '$newSubs جديد', Colors.green),
                const SizedBox(width: 8)
              ],
              if (updated > 0)
                _logChip(Icons.update, '$updated محدث', Colors.orange),
              const Spacer(),
              Text('$durationث',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            ]),
          ],
          if (!success && error != null) ...[
            const SizedBox(height: 4),
            Text(error,
                style: TextStyle(fontSize: 11, color: Colors.red.shade600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ],
        ]),
      ),
    );
  }

  Widget _logChip(IconData icon, String text, Color color) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: color),
      const SizedBox(width: 3),
      Text(text,
          style: TextStyle(
              fontSize: 11, color: color, fontWeight: FontWeight.w500)),
    ]);
  }
}
