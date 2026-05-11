import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../services/custom_auth_service.dart';
import '../../services/vps_auth_service.dart';
import '../../services/ftth_settings_service.dart';
import '../../services/vps_sync_service.dart';
import '../../services/vps_upload_service.dart';
import '../../services/local_database_service.dart';
import '../../services/auth_service.dart';
import '../../services/sync_service.dart';

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
  bool _isMasterSync = false;

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
  String _refetchStage = '';
  double? _refetchProgress;

  // إحصائيات تفصيلية
  Map<String, dynamic>? _detailedStats;
  bool _clearing = false;

  // حماية من إعادة عرض "قيد التنفيذ" بعد الإلغاء مباشرة
  DateTime? _cancelledAt;

  // تقدم المزامنة الحية
  String? _syncStage;
  int _syncProgress = 0;
  String? _syncMessage;
  int _syncFetchedCount = 0;
  int _syncTotalCount = 0;

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
          _isMasterSync = settings['isMasterSyncEnabled'] ?? false;
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
          // مسح الخطأ القديم عندما المزامنة شغالة
          if (_isSyncInProgress) _lastSyncError = null;
          // تقدم المزامنة
          _syncStage = status['syncStage'];
          _syncProgress = status['syncProgress'] ?? 0;
          _syncMessage = status['syncMessage'];
          _syncFetchedCount = status['syncFetchedCount'] ?? 0;
          _syncTotalCount = status['syncTotalCount'] ?? 0;
        }
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
    _loadLogs();
    _loadMissingStats();
    _loadDetailedStats();
    // إذا المزامنة قيد التنفيذ — نبدأ polling كل 4 ثواني
    if (_isSyncInProgress) _startProgressPolling();
  }

  void _startProgressPolling() {
    Future.delayed(const Duration(seconds: 30), () {
      if (!mounted) return;
      if (!_isSyncInProgress) return; // توقف إذا انتهت
      _loadSettings(); // سيعيد استدعاء _startProgressPolling إذا لا زالت تعمل
    });
  }

  Future<void> _loadMissingStats() async {
    if (_companyId == null) return;
    final stats = await FtthSettingsService.getMissingStats(_companyId!);
    if (mounted) setState(() => _missingStats = stats);
  }

  Future<void> _loadDetailedStats() async {
    if (_companyId == null) return;
    final stats = await FtthSettingsService.getDetailedStats(_companyId!);
    if (mounted) setState(() => _detailedStats = stats);
  }

  Future<void> _clearData(String type, String label) async {
    if (_companyId == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('مسح $label', style: const TextStyle(fontSize: 14)),
          content: Text('هل أنت متأكد من مسح $label من السيرفر؟',
              style: const TextStyle(fontSize: 13)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('مسح')),
          ],
        ),
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _clearing = true);
    final result = await FtthSettingsService.clearData(_companyId!, type);
    if (!mounted) return;
    setState(() => _clearing = false);
    if (result != null) {
      _showSnack(result['message'] ?? 'تم المسح');
      _loadSettings();
      _loadDetailedStats();
      _loadMissingStats();
    } else {
      _showSnack('فشل المسح', isError: true);
    }
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
      isMasterSyncEnabled: _isMasterSync,
    );
    // حفظ إعدادات Master محلياً أيضاً (للقراءة السريعة بدون API)
    await VpsUploadService.saveLocalSettings(
      isMasterSyncEnabled: _isMasterSync,
      syncStartHour: _syncStartHour,
      syncEndHour: _syncEndHour,
      syncIntervalMinutes: _syncInterval,
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

    if (_isMasterSync) {
      // الجهاز الرئيسي: يجلب الناقصين محلياً من FTTH ثم يرفع للسيرفر
      try {
        final token = await AuthService.instance.getAccessToken();
        if (token == null || token.isEmpty) {
          if (mounted) setState(() => _refetching = false);
          _showSnack('لا يوجد توكن FTTH', isError: true);
          return;
        }

        // جلب الهواتف الناقصة
        if (mounted) setState(() { _refetchStage = 'جلب الهواتف الناقصة...'; _refetchProgress = 0; });
        await SyncService().fetchPhoneNumbers(
          token: token,
          onProgress: (p) {
            if (mounted) setState(() => _refetchProgress = p.total > 0 ? p.current / p.total : 0);
          },
          onlyWithoutPhone: true,
        );

        // جلب التفاصيل الناقصة
        if (mounted) setState(() { _refetchStage = 'جلب التفاصيل الناقصة...'; _refetchProgress = 0; });
        await SyncService().fetchSubscriptionAddresses(
          token: token,
          onProgress: (p) {
            if (mounted) setState(() => _refetchProgress = p.total > 0 ? p.current / p.total : 0);
          },
          onlyWithoutDetails: true,
        );

        // رفع للسيرفر
        if (mounted) setState(() { _refetchStage = 'رفع البيانات للسيرفر...'; _refetchProgress = null; });
        final uploadResult = await VpsUploadService.instance.uploadToVps();

        if (!mounted) return;
        setState(() { _refetching = false; _refetchStage = ''; _refetchProgress = null; });

        // تحديث الإحصائيات قبل إظهار الرسالة
        await Future.wait([
          _loadMissingStats(),
          _loadDetailedStats(),
        ]);
        if (!mounted) return;
        _loadSettings();

        // فحص هل بقي ناقص بعد الجلب
        final newMissing = _missingStats;
        final stillMissingPhone = newMissing?['withoutPhone'] ?? 0;
        final stillMissingDetails = newMissing?['withoutDetails'] ?? 0;
        final hasRemaining = stillMissingPhone > 0 || stillMissingDetails > 0;

        if (uploadResult.success) {
          _showSnack(hasRemaining
              ? 'اكتمل الجلب — بقي $stillMissingPhone بدون هاتف و $stillMissingDetails بدون تفاصيل (غير متوفرة في FTTH)'
              : 'تم جلب كل البيانات الناقصة ورفعها للسيرفر');
        } else {
          _showSnack('فشل الرفع: ${uploadResult.error}', isError: true);
        }
      } catch (e) {
        if (mounted) setState(() { _refetching = false; _refetchStage = ''; _refetchProgress = null; });
        _showSnack('خطأ: $e', isError: true);
      }
    } else {
      // الجهاز العادي: يطلب من السيرفر أن يزامن
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
        _cardRow(_buildSyncStatusCard(), _isMasterSync ? _buildMasterUploadStatusCard() : _buildVpsDownloadCard()),
        const SizedBox(height: 8),
        _cardRow(_buildCredentialsCard(), _buildSyncSettingsCard()),
        const SizedBox(height: 8),
        _cardRow(_isMasterSync ? _buildVpsDownloadCard() : _buildCompletionProgressCard(), _buildMissingDataCard()),
        const SizedBox(height: 8),
        _cardRow(_isMasterSync ? _buildCompletionProgressCard() : _buildDataManagementCard(), _isMasterSync ? _buildDataManagementCard() : _buildSaveButton()),
        const SizedBox(height: 8),
        if (_isMasterSync) _buildSaveButton(),
        if (_isMasterSync) const SizedBox(height: 8),
      ]),
    );
  }

  /// صف من بطاقتين بنفس الارتفاع (بدون فراغات)
  Widget _cardRow(Widget left, Widget right) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: left),
          const SizedBox(width: 8),
          Expanded(child: right),
        ],
      ),
    );
  }

  Widget _buildCredentialsCard() {
    return Card(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Colors.black, width: 1.2),
      ),
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

  Widget _buildMasterUploadStatusCard() {
    return ListenableBuilder(
      listenable: VpsUploadService.instance,
      builder: (context, _) {
        final svc = VpsUploadService.instance;
        final lastResult = svc.lastResult;
        final isWorking = svc.isUploading || svc.isAutoSyncing;

        return Card(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: Colors.black, width: 1.2),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.cloud_sync_rounded, size: 18, color: Colors.green.shade600),
                const SizedBox(width: 6),
                const Text('حالة الجهاز الرئيسي',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                const Spacer(),
                if (isWorking)
                  _badge(svc.isAutoSyncing ? 'مزامنة تلقائية' : 'جاري الرفع', Colors.green),
              ]),
              const Divider(height: 16),

              // حالة الرفع الحالية
              if (isWorking) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          value: svc.progress > 0 ? svc.progress : null,
                          color: Colors.green.shade600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(svc.statusMessage,
                            style: TextStyle(fontSize: 11, color: Colors.green.shade800, fontWeight: FontWeight.w500),
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (svc.progress > 0)
                        Text('${(svc.progress * 100).toInt()}%',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green.shade700)),
                    ]),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: svc.progress > 0 ? svc.progress : null,
                        minHeight: 6,
                        backgroundColor: Colors.green.shade100,
                        valueColor: AlwaysStoppedAnimation(Colors.green.shade600),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 10),
              ],

              // آخر نتيجة رفع
              if (!isWorking && lastResult != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: lastResult.success ? Colors.green.shade50 : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(
                        lastResult.success ? Icons.check_circle : Icons.error_outline,
                        size: 16,
                        color: lastResult.success ? Colors.green.shade700 : Colors.red.shade700,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        lastResult.success ? 'آخر رفع ناجح' : 'فشل آخر رفع',
                        style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600,
                          color: lastResult.success ? Colors.green.shade700 : Colors.red.shade700,
                        ),
                      ),
                    ]),
                    if (lastResult.success) ...[
                      const SizedBox(height: 6),
                      Wrap(spacing: 12, children: [
                        _miniStat('المجموع', lastResult.uploadedCount, Colors.green),
                        _miniStat('جديد', lastResult.newCount, Colors.blue),
                        _miniStat('محدّث', lastResult.updatedCount, Colors.orange),
                        _miniStat('بدون تغيير', lastResult.skippedCount, Colors.grey),
                      ]),
                    ],
                    if (!lastResult.success && lastResult.error != null) ...[
                      const SizedBox(height: 4),
                      Text(lastResult.error!, style: TextStyle(fontSize: 11, color: Colors.red.shade600)),
                    ],
                  ]),
                ),
                const SizedBox(height: 10),
              ],

              // معلومات المقارنة: سيرفر vs محلي
              Row(children: [
                Expanded(child: _infoBox('السيرفر', _subscriberCount, Icons.cloud_rounded, Colors.blue)),
                const SizedBox(width: 8),
                Expanded(child: FutureBuilder<int>(
                  future: LocalDatabaseService.instance.getStatistics().then((s) => s['subscribers'] ?? 0),
                  builder: (ctx, snap) => _infoBox('المحلي', snap.data ?? 0, Icons.storage_rounded, Colors.teal),
                )),
              ]),
              const SizedBox(height: 10),

              // زر المزامنة اليدوية (جلب + رفع)
              _buildManualMasterSyncButton(svc),
              const SizedBox(height: 6),
              // زر الرفع فقط (بدون جلب)
              _buildUploadButton(),
            ]),
          ),
        );
      },
    );
  }

  Widget _miniStat(String label, int count, Color color) {
    return Text('$label: ${NumberFormat('#,###').format(count)}',
        style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600));
  }

  Widget _infoBox(String label, int count, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
          Text(NumberFormat('#,###').format(count),
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
        ]),
      ]),
    );
  }

  Widget _buildManualMasterSyncButton(VpsUploadService svc) {
    final isWorking = svc.isUploading || svc.isAutoSyncing;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: isWorking
            ? null
            : () async {
                final token = await AuthService.instance.getAccessToken();
                if (token == null || token.isEmpty) {
                  _showSnack('لا يوجد توكن FTTH — سجّل الدخول أولاً', isError: true);
                  return;
                }
                // جلب من FTTH
                setState(() => _statusMessage = 'جلب البيانات من FTTH...');
                final syncResult = await SyncService().fullSync(
                  token: token,
                  onProgress: (p) {
                    if (mounted) setState(() => _statusMessage = p.message);
                  },
                );
                if (!mounted) return;
                if (!syncResult.success) {
                  _showSnack(_translateError(syncResult.error ?? 'خطأ'), isError: true);
                  setState(() => _statusMessage = '');
                  return;
                }
                // رفع للسيرفر
                setState(() => _statusMessage = 'رفع للسيرفر...');
                final uploadResult = await VpsUploadService.instance.uploadToVps();
                if (!mounted) return;
                setState(() => _statusMessage = '');
                _showSnack(
                  uploadResult.success
                      ? 'تم جلب ${syncResult.subscribersCount} مشترك ورفع ${uploadResult.uploadedCount} للسيرفر'
                      : _translateError(uploadResult.error ?? 'خطأ'),
                  isError: !uploadResult.success,
                );
                _loadSettings();
              },
        icon: isWorking
            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.sync_rounded, size: 18),
        label: Text(isWorking ? _statusMessage.isNotEmpty ? _statusMessage : 'جاري...' : 'مزامنة الآن (جلب + رفع)',
            style: const TextStyle(fontSize: 12)),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue.shade700,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  String _statusMessage = '';

  Widget _buildUploadButton() {
    return ListenableBuilder(
      listenable: VpsUploadService.instance,
      builder: (context, _) {
        final svc = VpsUploadService.instance;
        if (svc.isUploading) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LinearProgressIndicator(value: svc.progress, minHeight: 6,
                  backgroundColor: Colors.green.shade50, color: Colors.green),
              const SizedBox(height: 4),
              Text(svc.statusMessage,
                  style: const TextStyle(fontSize: 11, color: Colors.green),
                  textAlign: TextAlign.center),
            ],
          );
        }
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () async {
              final result = await VpsUploadService.instance.uploadToVps();
              if (!mounted) return;
              _showSnack(
                result.success
                    ? 'تم رفع ${result.uploadedCount} مشترك (جديد: ${result.newCount}, محدّث: ${result.updatedCount})'
                    : 'فشل الرفع: ${result.error}',
                isError: !result.success,
              );
              _loadSettings();
            },
            icon: const Icon(Icons.cloud_upload, size: 18),
            label: const Text('رفع البيانات المحلية للسيرفر', style: TextStyle(fontSize: 12)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSyncSettingsCard() {
    return Card(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Colors.black, width: 1.2),
      ),
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
            title: Text(
                _isMasterSync ? 'هذا الجهاز هو المزامن الرئيسي ✅' : 'هذا الجهاز هو المزامن الرئيسي',
                style: TextStyle(fontSize: 13, fontWeight: _isMasterSync ? FontWeight.bold : FontWeight.normal,
                    color: _isMasterSync ? Colors.green.shade700 : null)),
            subtitle: Text(
                _isMasterSync
                    ? 'يجلب البيانات من FTTH ويرفعها للسيرفر — بقية الأجهزة تقرأ من السيرفر'
                    : 'عند التفعيل: هذا الجهاز يرفع البيانات للسيرفر بدل أن يجلبها السيرفر مباشرة',
                style: const TextStyle(fontSize: 11)),
            value: _isMasterSync,
            onChanged: (v) => setState(() => _isMasterSync = v),
            activeColor: Colors.green,
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
          if (_isMasterSync) ...[
            const SizedBox(height: 4),
            _buildUploadButton(),
            const SizedBox(height: 8),
          ],
          SwitchListTile(
            title: const Text('المزامنة التلقائية',
                style: TextStyle(fontSize: 13)),
            subtitle: Text(
                _isMasterSync
                    ? 'غير مطلوبة — المزامنة تتم من هذا الجهاز'
                    : 'مزامنة تلقائية من FTTH',
                style: const TextStyle(fontSize: 11)),
            value: _isMasterSync ? false : _autoSync,
            onChanged: _isMasterSync ? null : (v) => setState(() => _autoSync = v),
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

  /// ترجمة أخطاء المزامنة للعربي
  String _translateError(String error) {
    if (error.contains('Connection closed') || error.contains('ClientException')) return 'سيرفر FTTH أغلق الاتصال — حاول مرة أخرى لاحقاً';
    if (error.contains('sending the request')) return 'فشل الاتصال بسيرفر FTTH — قد يكون محظوراً مؤقتاً';
    if (error.contains('SocketException') || error.contains('خطأ اتصال')) return 'لا يوجد اتصال بسيرفر FTTH — تحقق من الشبكة';
    if (error.contains('saving the entity')) return 'فشل حفظ البيانات في قاعدة البيانات';
    if (error.contains('login') || error.contains('Login')) return 'فشل تسجيل الدخول — تحقق من بيانات الدخول';
    if (error.contains('timeout') || error.contains('Timeout')) return 'انتهت مهلة الاتصال — السيرفر لا يستجيب';
    if (error.contains('401')) return 'انتهت صلاحية الجلسة — أعد المحاولة';
    if (error.contains('418')) return 'سيرفر FTTH رفض الطلب — حاول لاحقاً';
    if (error.contains('429')) return 'كثرة الطلبات — انتظر قليلاً ثم أعد المحاولة';
    return 'خطأ في المزامنة — حاول مرة أخرى';
  }

  Widget _buildSyncStatusCard() {
    final hasSync = _lastSyncAt != null;
    // إظهار الخطأ فقط عندما المزامنة ليست شغالة
    final hasError = !_isSyncInProgress && _lastSyncError != null && _lastSyncError!.isNotEmpty;

    return Card(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Colors.black, width: 1.2),
      ),
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
            if (_isSyncInProgress)
              _badge('قيد التنفيذ $_syncProgress%', Colors.orange),
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
              _isSyncInProgress
                  ? 'جاري المزامنة...'
                  : hasError
                      ? 'خطأ'
                      : hasSync
                          ? 'ناجحة'
                          : 'لم تتم',
              icon: _isSyncInProgress
                  ? Icons.sync_rounded
                  : hasError
                      ? Icons.error_outline
                      : Icons.check_circle_outline,
              color: _isSyncInProgress
                  ? Colors.blue
                  : hasError
                      ? Colors.red
                      : hasSync
                          ? Colors.green
                          : Colors.grey),
          if (!_isSyncInProgress && _consecutiveFailures > 0) ...[
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
              child: Text(_translateError(_lastSyncError!),
                  style: TextStyle(fontSize: 11, color: Colors.red.shade700)),
            ),
          ],
          // ═══ شريط التقدم الحي ═══
          if (_isSyncInProgress && _syncMessage != null && _syncMessage!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      value: _syncProgress > 0 ? _syncProgress / 100.0 : null,
                      color: Colors.blue.shade600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _syncMessage!,
                      style: TextStyle(fontSize: 11, color: Colors.blue.shade800, fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '$_syncProgress%',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue.shade700),
                  ),
                ]),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _syncProgress / 100.0,
                    minHeight: 6,
                    backgroundColor: Colors.blue.shade100,
                    valueColor: AlwaysStoppedAnimation(Colors.blue.shade600),
                  ),
                ),
                if (_syncFetchedCount > 0 || _syncTotalCount > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${NumberFormat('#,###').format(_syncFetchedCount)} / ${NumberFormat('#,###').format(_syncTotalCount)}',
                    style: TextStyle(fontSize: 10, color: Colors.blue.shade600),
                  ),
                ],
              ]),
            ),
          ],
          const SizedBox(height: 10),
          if (_isMasterSync)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(children: [
                Icon(Icons.info_outline, size: 14, color: Colors.green.shade700),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('المزامنة تتم من هذا الجهاز — السيرفر لا يزامن مباشرة',
                      style: TextStyle(fontSize: 11, color: Colors.green.shade700)),
                ),
              ]),
            )
          else
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
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: Colors.black, width: 1.2),
          ),
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
    final total = stats?['total'] ?? 0;
    final missingFat = stats?['withoutFat'] ?? 0;
    final missingFdt = stats?['withoutFdt'] ?? 0;
    final missingPhone = stats?['withoutPhone'] ?? 0;
    final missingAddress = stats?['withoutDetails'] ?? 0;
    final hasMissing = missingFat > 0 || missingPhone > 0 || missingAddress > 0;

    return Card(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Colors.black, width: 1.2),
      ),
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
            if (hasMissing && !_refetching) ...[
              const SizedBox(height: 6),
              Text('هذه البيانات قد تكون غير متوفرة في نظام FTTH (مشتركين بدون أجهزة أو حسابات معلّقة)',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade500, fontStyle: FontStyle.italic)),
            ],
            if (hasMissing) ...[
              const SizedBox(height: 8),
              if (_refetching) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      SizedBox(width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange.shade600,
                          value: _refetchProgress,
                        )),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_refetchStage,
                          style: TextStyle(fontSize: 11, color: Colors.orange.shade800, fontWeight: FontWeight.w500))),
                      if (_refetchProgress != null)
                        Text('${(_refetchProgress! * 100).toInt()}%',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange.shade700)),
                    ]),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _refetchProgress,
                        minHeight: 6,
                        backgroundColor: Colors.orange.shade100,
                        valueColor: AlwaysStoppedAnimation(Colors.orange.shade600),
                      ),
                    ),
                  ]),
                ),
              ] else
              SizedBox(
                width: double.infinity,
                height: 36,
                child: ElevatedButton.icon(
                  onPressed: _isSyncInProgress ? null : _refetchMissing,
                  icon: const Icon(Icons.download_for_offline_rounded, size: 18),
                  label: Text(
                    _isMasterSync
                        ? 'جلب الناقصة من FTTH ورفعها للسيرفر'
                        : 'جلب البيانات الناقصة',
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
            ] else ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.check_circle, size: 16, color: Colors.green.shade700),
                  const SizedBox(width: 6),
                  Text('لا توجد بيانات ناقصة', style: TextStyle(fontSize: 12, color: Colors.green.shade700)),
                ]),
              ),
            ],
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

  Widget _buildCompletionProgressCard() {
    final s = _detailedStats;
    if (s == null || (s['total'] ?? 0) == 0) {
      return Card(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: Colors.black, width: 1.2),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Icon(Icons.analytics_rounded, color: Colors.grey.shade400, size: 20),
            const SizedBox(width: 8),
            Text('لا توجد بيانات — قم بتشغيل المزامنة أولاً',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.refresh, size: 18),
              onPressed: _loadDetailedStats,
              tooltip: 'تحديث',
            ),
          ]),
        ),
      );
    }

    final total = s['total'] ?? 0;
    final overallPct = (s['overallPct'] ?? 0).toDouble();
    final withPhone = s['withPhone'] ?? 0;
    final withDetails = s['withDetails'] ?? 0;
    final withUsername = s['withUsername'] ?? 0;
    final phonePct = (s['phonePct'] ?? 0).toDouble();
    final detailsPct = (s['detailsPct'] ?? 0).toDouble();
    final usernamePct = (s['usernamePct'] ?? 0).toDouble();
    final active = s['active'] ?? 0;
    final expired = s['expired'] ?? 0;

    return Card(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Colors.black, width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.analytics_rounded, color: Colors.deepPurple, size: 18),
            const SizedBox(width: 6),
            const Text('نسبة اكتمال البيانات',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: overallPct >= 90
                    ? Colors.green.shade50
                    : overallPct >= 60
                        ? Colors.orange.shade50
                        : Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${overallPct.toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: overallPct >= 90
                      ? Colors.green.shade700
                      : overallPct >= 60
                          ? Colors.orange.shade700
                          : Colors.red.shade700,
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              icon: const Icon(Icons.refresh, size: 18),
              onPressed: _loadDetailedStats,
              tooltip: 'تحديث',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
          ]),
          const SizedBox(height: 10),
          // شريط الاكتمال الإجمالي
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: overallPct / 100,
              minHeight: 8,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation(
                overallPct >= 90 ? Colors.green : overallPct >= 60 ? Colors.orange : Colors.red,
              ),
            ),
          ),
          const SizedBox(height: 12),
          // تفاصيل كل قسم
          _progressRow('الاشتراكات', total, total, 100, Colors.blue),
          const SizedBox(height: 6),
          _progressRow('التفاصيل (FDT/FAT/GPS)', withDetails, total, detailsPct, Colors.teal),
          const SizedBox(height: 6),
          _progressRow('اسم المستخدم', withUsername, total, usernamePct, Colors.indigo),
          const SizedBox(height: 6),
          _progressRow('أرقام الهواتف', withPhone, total, phonePct, Colors.deepOrange),
          const SizedBox(height: 10),
          // الحالات
          Row(children: [
            _statusChip('فعال', active, Colors.green),
            const SizedBox(width: 8),
            _statusChip('منتهي', expired, Colors.red),
            const SizedBox(width: 8),
            _statusChip('الإجمالي', total, Colors.blue),
          ]),
        ]),
      ),
    );
  }

  Widget _progressRow(String label, int current, int total, double pct, Color color) {
    return Row(children: [
      SizedBox(
        width: 140,
        child: Text(label, style: const TextStyle(fontSize: 11)),
      ),
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: total > 0 ? current / total : 0,
            minHeight: 6,
            backgroundColor: Colors.grey.shade100,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ),
      const SizedBox(width: 8),
      SizedBox(
        width: 90,
        child: Text(
          '$current/$total (${pct.toStringAsFixed(0)}%)',
          style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
          textAlign: TextAlign.left,
        ),
      ),
    ]);
  }

  Widget _statusChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$label: ${NumberFormat('#,###').format(count)}',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }

  Widget _buildDataManagementCard() {
    return Card(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Colors.black, width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.delete_sweep_rounded, color: Colors.red.shade400, size: 18),
            const SizedBox(width: 6),
            const Text('إدارة بيانات السيرفر',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ]),
          const SizedBox(height: 10),
          if (_clearing)
            const Center(child: Padding(
              padding: EdgeInsets.all(12),
              child: CircularProgressIndicator(strokeWidth: 2),
            ))
          else
            Wrap(spacing: 8, runSpacing: 8, children: [
              _clearButton('أرقام الهواتف', 'phones', Icons.phone_disabled, Colors.orange),
              _clearButton('تفاصيل الاشتراكات', 'details', Icons.info_outline, Colors.teal),
              _clearButton('كل الاشتراكات', 'subscriptions', Icons.people_outline, Colors.red),
              _clearButton('مسح الكل', 'all', Icons.delete_forever, Colors.red.shade800),
            ]),
        ]),
      ),
    );
  }

  Widget _clearButton(String label, String type, IconData icon, Color color) {
    return OutlinedButton.icon(
      onPressed: () => _clearData(type, label),
      icon: Icon(icon, size: 15, color: color),
      label: Text(label, style: TextStyle(fontSize: 11, color: color)),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: color.withValues(alpha: 0.3)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildSaveButton() {
    return Card(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Colors.black, width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: SizedBox(
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
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Colors.black, width: 1.2),
      ),
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
