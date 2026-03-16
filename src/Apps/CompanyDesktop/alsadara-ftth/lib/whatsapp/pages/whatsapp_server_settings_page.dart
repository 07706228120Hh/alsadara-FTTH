/// صفحة إعدادات WhatsApp Server
/// ربط رقم الشركة عبر QR Code
/// عرض حالة الاتصال وإرسال تجريبي
library;

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' as intl;
import '../services/whatsapp_server_service.dart';
import '../services/whatsapp_message_log_service.dart';

class WhatsAppServerSettingsPage extends StatefulWidget {
  final String tenantId;
  final String? tenantName;

  const WhatsAppServerSettingsPage({
    required this.tenantId,
    this.tenantName,
    super.key,
  });

  @override
  State<WhatsAppServerSettingsPage> createState() =>
      _WhatsAppServerSettingsPageState();
}

class _WhatsAppServerSettingsPageState
    extends State<WhatsAppServerSettingsPage> {
  // حالة الاتصال
  bool _isServerOnline = false;
  bool _isConnected = false;
  String? _connectedPhone;
  String? _connectedName;

  // QR Code
  String? _qrImage;
  bool _isLoadingQR = false;
  DateTime? _lastQRFetch;
  static const int _qrValiditySeconds = 120;
  String? _statusMessage;

  // عام
  bool _isLoading = true;
  Timer? _statusTimer;
  Timer? _keepAliveTimer; // مراقبة مستمرة للاتصال حتى عند الاتصال

  // إعدادات السيرفر
  final _serverUrlController = TextEditingController();
  bool _isEditingServer = false;

  // إعدادات الإرسال الجماعي
  int _bulkDelayValue = 5;
  String _bulkDelayUnit = 'seconds';

  // سجل الرسائل
  List<WhatsAppMessageLogEntry> _logEntries = [];
  Map<String, int> _logStats = {};
  DateTime? _logFromDate;
  DateTime? _logToDate;
  bool _isLoadingLogs = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _keepAliveTimer?.cancel();
    _serverUrlController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    final serverUrl = await WhatsAppServerService.getServerUrl();
    _serverUrlController.text = serverUrl;

    final bulkSettings = await WhatsAppServerService.getBulkSettings(
      tenantId: widget.tenantId,
    );
    _bulkDelayValue = bulkSettings['delayValue'] ?? 5;
    _bulkDelayUnit = bulkSettings['delayUnit'] ?? 'seconds';

    await _checkServerAndStatus();
    await _loadMessageLogs();

    setState(() => _isLoading = false);
  }

  Future<void> _loadMessageLogs() async {
    setState(() => _isLoadingLogs = true);
    try {
      _logEntries = await WhatsAppMessageLogService.getLogs(
        fromDate: _logFromDate,
        toDate: _logToDate,
      );
      _logStats = await WhatsAppMessageLogService.getStats(
        fromDate: _logFromDate,
        toDate: _logToDate,
      );
    } catch (_) {}
    if (mounted) setState(() => _isLoadingLogs = false);
  }

  Future<void> _checkServerAndStatus() async {
    final isOnline = await WhatsAppServerService.isServerOnline();
    setState(() => _isServerOnline = isOnline);

    if (isOnline) {
      await _checkStatus();
    }
  }

  Future<void> _checkStatus() async {
    final status = await WhatsAppServerService.getStatus(widget.tenantId);

    if (mounted) {
      final connected = status['connected'] == true;
      final wasConnected = _isConnected;

      setState(() {
        _isConnected = connected;
        _connectedPhone = status['phone'];
        _connectedName = status['name'];
      });

      if (connected) {
        final serverUrl = _serverUrlController.text.trim();
        if (serverUrl.isNotEmpty) {
          await WhatsAppServerService.saveServerUrl(serverUrl);
        }
        // شغّل مراقبة مستمرة عند الاتصال
        _startKeepAlive();
      }

      // اكتُشف انقطاع الاتصال
      if (!connected && wasConnected) {
        _keepAliveTimer?.cancel();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '⚠️ انقطع اتصال الواتساب — اضغط "إنشاء جلسة" لإعادة الاتصال',
                style: const TextStyle(fontFamily: 'Cairo'),
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 5),
            ),
          );
        }
        return;
      }

      if (!_isConnected && !_isLoadingQR) {
        // عند التهيئة: فقط اجلب QR موجود دون إنشاء جلسة جديدة
        if (_qrImage == null || _isQRExpired()) {
          _fetchQR();
        }
      }

      if (_isConnected && _qrImage != null) {
        setState(() {
          _qrImage = null;
          _lastQRFetch = null;
        });
      }
    }
  }

  /// مراقبة مستمرة كل 15 ثانية حتى عند الاتصال
  void _startKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) async {
        if (!mounted) return;
        final status = await WhatsAppServerService.getStatus(widget.tenantId);
        if (!mounted) return;
        final connected = status['connected'] == true;
        if (!connected && _isConnected) {
          // انقطع الاتصال
          _keepAliveTimer?.cancel();
          setState(() {
            _isConnected = false;
            _connectedPhone = null;
            _connectedName = null;
            _qrImage = null;
            _lastQRFetch = null;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '⚠️ انقطع اتصال الواتساب — اضغط "إنشاء جلسة" لإعادة الاتصال',
                style: const TextStyle(fontFamily: 'Cairo'),
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      },
    );
  }

  bool _isQRExpired() {
    if (_lastQRFetch == null) return true;
    final elapsed = DateTime.now().difference(_lastQRFetch!).inSeconds;
    return elapsed > _qrValiditySeconds;
  }

  Future<void> _createSession() async {
    setState(() {
      _isLoadingQR = true;
      _qrImage = null;
      _statusMessage = 'جاري التحقق من حالة الاتصال...';
    });

    // ── تحقق أولاً: هل الجلسة متصلة فعلاً؟ ──
    final currentStatus =
        await WhatsAppServerService.getStatus(widget.tenantId);
    if (currentStatus['connected'] == true && mounted) {
      setState(() {
        _isConnected = true;
        _connectedPhone = currentStatus['phone'];
        _connectedName = currentStatus['name'];
        _qrImage = null;
        _lastQRFetch = null;
        _isLoadingQR = false;
        _statusMessage = null;
      });
      _startKeepAlive();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✅ الواتساب متصل بالفعل — ${currentStatus['name'] ?? ''} (${currentStatus['phone'] ?? ''})',
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _statusMessage = 'جاري إنشاء الجلسة...');

    // حذف أي جلسة عالقة (قد تكون في حالة "connecting")
    await WhatsAppServerService.disconnect(widget.tenantId);
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    final sessionRaw =
        await WhatsAppServerService.createSessionRaw(widget.tenantId);
    debugPrint('📤 createSession response: $sessionRaw');

    // محاولات متعددة للحصول على QR (كل 2 ثانية، أقصى 30 محاولة = 60 ثانية)
    String? qr;
    for (int i = 0; i < 30; i++) {
      await Future.delayed(const Duration(seconds: 2));

      if (!mounted) return;

      // تحقق إذا اتصل تلقائياً أثناء الانتظار
      final pollStatus =
          await WhatsAppServerService.getStatus(widget.tenantId);
      if (pollStatus['connected'] == true && mounted) {
        setState(() {
          _isConnected = true;
          _connectedPhone = pollStatus['phone'];
          _connectedName = pollStatus['name'];
          _qrImage = null;
          _lastQRFetch = null;
          _isLoadingQR = false;
          _statusMessage = null;
        });
        _startKeepAlive();
        return;
      }

      setState(() => _statusMessage = 'جاري توليد كود QR... (${i + 1}/30)');

      // جرب /qr-image أولاً ثم /status
      qr = await WhatsAppServerService.getQRImage(widget.tenantId);
      qr ??= await WhatsAppServerService.getQRFromStatus(widget.tenantId);
      if (qr != null) break;
    }

    if (mounted) {
      setState(() {
        _qrImage = qr;
        _lastQRFetch = qr != null ? DateTime.now() : null;
        _isLoadingQR = false;
        _statusMessage = null;
      });

      if (qr != null) {
        _startConnectionMonitor();
      } else {
        // جلب الردود الخام لعرضها للتشخيص
        final rawResponse =
            await WhatsAppServerService.getQRImageRaw(widget.tenantId);
        final statusRaw =
            await WhatsAppServerService.getStatusRaw(widget.tenantId);

        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text('❌ تعذّر توليد QR',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('TenantId: ${widget.tenantId}',
                        style: GoogleFonts.cairo(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 12),
                    Text('POST /session (إنشاء جلسة):',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SelectableText(
                        sessionRaw,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text('GET /qr-image:',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SelectableText(
                        rawResponse,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text('GET /status:',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SelectableText(
                        statusRaw,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('حسناً', style: GoogleFonts.cairo()),
                ),
              ],
            ),
          );
        }
      }
    }
  }

  /// مراقبة سريعة كل 3 ثوان أثناء انتظار مسح QR
  void _startConnectionMonitor() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) async {
        final status = await WhatsAppServerService.getStatus(widget.tenantId);
        if (mounted) {
          final connected = status['connected'] == true;
          if (connected) {
            _statusTimer?.cancel();

            final serverUrl = _serverUrlController.text.trim();
            if (serverUrl.isNotEmpty) {
              await WhatsAppServerService.saveServerUrl(serverUrl);
            }

            setState(() {
              _isConnected = true;
              _connectedPhone = status['phone'];
              _connectedName = status['name'];
              _qrImage = null;
              _lastQRFetch = null;
            });

            // ابدأ المراقبة المستمرة بعد الاتصال
            _startKeepAlive();
          }
        }
      },
    );
  }

  Future<void> _fetchQR() async {
    if (_isLoadingQR) return;
    if (!mounted) return;
    setState(() => _isLoadingQR = true);

    final qr = await WhatsAppServerService.getQRImage(widget.tenantId);

    if (mounted) {
      setState(() {
        _qrImage = qr;
        _lastQRFetch = qr != null ? DateTime.now() : null;
        _isLoadingQR = false;
      });
    }
  }

  /// إعادة تشغيل الجلسة (بدون QR)
  Future<void> _restartSession() async {
    setState(() => _statusMessage = 'جاري إعادة تشغيل الجلسة...');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🔄 جاري إعادة تشغيل الجلسة...', style: GoogleFonts.cairo()),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 3),
      ),
    );

    final result = await WhatsAppServerService.restartSession(widget.tenantId);

    if (!mounted) return;

    if (result['restarted'] == true) {
      // انتظر حتى يعاد الاتصال
      setState(() {
        _isConnected = false;
        _statusMessage = 'جاري إعادة الاتصال...';
      });

      // محاولة الانتظار حتى يعود الاتصال (أقصى 30 ثانية)
      for (int i = 0; i < 15; i++) {
        await Future.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        final status = await WhatsAppServerService.getStatus(widget.tenantId);
        if (status['connected'] == true) {
          setState(() {
            _isConnected = true;
            _connectedPhone = status['phone'];
            _connectedName = status['name'];
            _statusMessage = null;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ تم إعادة تشغيل الجلسة بنجاح!', style: GoogleFonts.cairo()),
              backgroundColor: Colors.green,
            ),
          );
          _startKeepAlive();
          return;
        }
      }

      // لم يعد الاتصال — ربما يحتاج QR جديد
      if (mounted) {
        setState(() => _statusMessage = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ لم يتم إعادة الاتصال — قد تحتاج لمسح QR جديد', style: GoogleFonts.cairo()),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } else {
      setState(() => _statusMessage = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⏳ تم تخطي الإعادة — انتظر قليلاً ثم حاول مجدداً', style: GoogleFonts.cairo()),
          backgroundColor: Colors.grey,
        ),
      );
    }
  }

  /// فحص صحة الجلسة
  Future<void> _checkHealth() async {
    final health = await WhatsAppServerService.getHealth(widget.tenantId);
    if (!mounted) return;

    final healthy = health['healthy'] == true;
    final status = health['status'] ?? 'unknown';
    final failures = health['consecutiveFailures'] ?? 0;
    final restarts = health['totalRestarts'] ?? 0;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              healthy ? Icons.check_circle : Icons.warning,
              color: healthy ? Colors.green : Colors.orange,
              size: 28,
            ),
            const SizedBox(width: 8),
            Text(
              healthy ? 'الجلسة سليمة' : 'الجلسة غير سليمة',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _healthRow('الحالة', status, healthy ? Colors.green : Colors.orange),
            _healthRow('أخطاء متتالية', '$failures', failures > 0 ? Colors.red : Colors.green),
            _healthRow('إعادات تشغيل', '$restarts', restarts > 0 ? Colors.orange : Colors.grey),
            if (health['phone'] != null) _healthRow('الرقم', health['phone'], Colors.blue),
            if (health['error'] != null) ...[
              const SizedBox(height: 8),
              Text('الخطأ:', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: Colors.red)),
              Text(health['error'], style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            ],
          ],
        ),
        actions: [
          if (!healthy)
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _restartSession();
              },
              icon: const Icon(Icons.refresh),
              label: Text('إعادة تشغيل', style: GoogleFonts.cairo()),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('إغلاق', style: GoogleFonts.cairo()),
          ),
        ],
      ),
    );
  }

  Widget _healthRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text('$label: ', style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(value, style: GoogleFonts.cairo(color: color, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _disconnect() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('قطع الاتصال'),
        content: const Text(
            'هل تريد قطع اتصال الواتساب؟\nستحتاج لمسح QR مرة أخرى للاتصال.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('قطع الاتصال'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await WhatsAppServerService.disconnect(widget.tenantId);
      setState(() {
        _isConnected = false;
        _connectedPhone = null;
        _qrImage = null;
      });
      await _createSession();
    }
  }

  Future<void> _sendTestMessage() async {
    final phoneController = TextEditingController();
    final messageController = TextEditingController(
      text: 'رسالة تجريبية من نظام إدارة الاشتراكات!\n\nتم إرسال هذه الرسالة تلقائياً للتأكد من عمل النظام.',
    );

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF25D366).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.send, color: Color(0xFF25D366)),
              ),
              const SizedBox(width: 12),
              Text('إرسال رسالة', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  textAlign: TextAlign.left,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    labelText: 'رقم الهاتف',
                    hintText: '07xxxxxxxxx',
                    prefixIcon: const Icon(Icons.phone),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.content_paste_go, size: 20),
                      tooltip: 'لصق',
                      onPressed: () async {
                        final data = await Clipboard.getData(Clipboard.kTextPlain);
                        if (data?.text != null) {
                          final clean = data!.text!.replaceAll(RegExp(r'[^\d+]'), '');
                          phoneController.text = clean;
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: messageController,
                  maxLines: 5,
                  textAlign: TextAlign.right,
                  decoration: InputDecoration(
                    labelText: 'نص الرسالة',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('إلغاء', style: GoogleFonts.cairo()),
            ),
            ElevatedButton.icon(
              onPressed: () {
                if (phoneController.text.trim().isNotEmpty && messageController.text.trim().isNotEmpty) {
                  Navigator.pop(ctx, {
                    'phone': phoneController.text.trim(),
                    'message': messageController.text.trim(),
                  });
                }
              },
              icon: const Icon(Icons.send, size: 18),
              label: Text('إرسال', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;
    final rawPhone = result['phone']!;
    final message = result['message']!;

    // تنسيق الرقم: تحويل محلي → دولي
    final phone = _formatPhoneToInternational(rawPhone);

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Row(
          children: [
            const SizedBox(
              width: 24, height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(width: 20),
            Text('جاري الإرسال...', style: GoogleFonts.cairo()),
          ],
        ),
      ),
    );

    final error = await WhatsAppServerService.sendMessageWithError(
      tenantId: widget.tenantId,
      phone: phone,
      message: message,
    );

    // تسجيل في السجل المحلي
    await WhatsAppMessageLogService.log(
      phone: phone,
      customerName: 'رسالة يدوية',
      system: 'server',
      operationType: 'manual',
      success: error == null,
      error: error,
    );

    if (mounted) Navigator.pop(context);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error == null
                ? '✅ تم إرسال الرسالة بنجاح!'
                : '❌ فشل الإرسال',
            style: GoogleFonts.cairo(),
          ),
          backgroundColor: error == null ? Colors.green : Colors.red,
          duration: const Duration(seconds: 8),
        ),
      );
      // تحديث السجلات
      _loadMessageLogs();
    }
  }

  Future<void> _saveServerUrl() async {
    final newUrl = _serverUrlController.text.trim();
    if (newUrl.isEmpty) return;

    await WhatsAppServerService.saveServerUrl(newUrl);
    setState(() => _isEditingServer = false);

    await _checkServerAndStatus();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ تم حفظ عنوان السيرفر')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'إعدادات WhatsApp Server',
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
          ),
          backgroundColor: const Color(0xFF25D366),
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              onPressed: _checkServerAndStatus,
              icon: const Icon(Icons.refresh),
              tooltip: 'تحديث',
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildServerStatusCard(),
                    const SizedBox(height: 16),
                    if (_isConnected) _buildConnectedCard() else _buildQRCard(),
                    const SizedBox(height: 16),
                    _buildServerSettingsCard(),
                    const SizedBox(height: 16),
                    _buildBulkSettingsCard(),
                    const SizedBox(height: 16),
                    _buildMessageLogCard(),
                    const SizedBox(height: 16),
                    _buildInfoCard(),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildServerStatusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // --- حالة السيرفر ---
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _isServerOnline
                    ? Colors.green.withOpacity(0.1)
                    : Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _isServerOnline ? Icons.cloud_done : Icons.cloud_off,
                color: _isServerOnline ? Colors.green : Colors.red,
                size: 24,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'السيرفر',
                    style: GoogleFonts.cairo(
                        fontSize: 12, color: Colors.grey[600]),
                  ),
                  Text(
                    _isServerOnline ? 'يعمل ✅' : 'متوقف ❌',
                    style: GoogleFonts.cairo(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: _isServerOnline ? Colors.green : Colors.red,
                    ),
                  ),
                ],
              ),
            ),

            // فاصل عمودي
            Container(
              width: 1,
              height: 40,
              color: Colors.grey[300],
              margin: const EdgeInsets.symmetric(horizontal: 12),
            ),

            // --- حالة جلسة واتساب ---
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _isConnected
                    ? Colors.green.withOpacity(0.1)
                    : Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _isConnected ? Icons.phone_android : Icons.phone_disabled,
                color: _isConnected ? Colors.green : Colors.orange,
                size: 24,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'جلسة واتساب',
                    style: GoogleFonts.cairo(
                        fontSize: 12, color: Colors.grey[600]),
                  ),
                  Text(
                    _isConnected ? 'متصل ✅' : 'غير متصل ⚠️',
                    style: GoogleFonts.cairo(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: _isConnected ? Colors.green : Colors.orange[800],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectedCard() {
    return Card(
      color: Colors.green[50],
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(50),
              ),
              child: const Icon(Icons.check, color: Colors.white, size: 60),
            ),
            const SizedBox(height: 20),
            Text(
              '✅ متصل بنجاح!',
              style: GoogleFonts.cairo(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.green[800],
              ),
            ),
            const SizedBox(height: 10),
            if (_connectedPhone != null) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.phone, color: Colors.green),
                  const SizedBox(width: 8),
                  Text(
                    _connectedPhone!,
                    style: GoogleFonts.cairo(fontSize: 18),
                  ),
                ],
              ),
            ],
            if (_connectedName != null) ...[
              const SizedBox(height: 5),
              Text(
                _connectedName!,
                style: GoogleFonts.cairo(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
              ),
            ],
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: _sendTestMessage,
                  icon: const Icon(Icons.send, size: 18),
                  label: Text('إرسال تجريبي', style: GoogleFonts.cairo(fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _restartSession,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text('إعادة تشغيل', style: GoogleFonts.cairo(fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _checkHealth,
                  icon: const Icon(Icons.health_and_safety, size: 18),
                  label: Text('فحص الصحة', style: GoogleFonts.cairo(fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _disconnect,
                  icon: const Icon(Icons.link_off, color: Colors.red, size: 18),
                  label: Text('قطع الاتصال',
                      style: GoogleFonts.cairo(color: Colors.red, fontSize: 13)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQRCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              '📱 ربط الواتساب',
              style: GoogleFonts.cairo(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'امسح الكود من تطبيق الواتساب',
              style: GoogleFonts.cairo(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 20),

            // QR Code
            if (_isLoadingQR)
              SizedBox(
                width: 250,
                height: 250,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(),
                    if (_statusMessage != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _statusMessage!,
                        style: GoogleFonts.cairo(color: Colors.grey[600], fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              )
            else if (_qrImage != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Image.memory(
                  base64Decode(_qrImage!.split(',').last),
                  width: 250,
                  height: 250,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.qr_code,
                    size: 250,
                    color: Colors.grey,
                  ),
                ),
              )
            else
              Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.qr_code_2, size: 80, color: Colors.grey[400]),
                    const SizedBox(height: 10),
                    Text(
                      'اضغط لإنشاء جلسة',
                      style: GoogleFonts.cairo(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 20),

            ElevatedButton.icon(
              onPressed: _isLoadingQR ? null : _createSession,
              icon: Icon(_qrImage == null ? Icons.play_arrow : Icons.refresh),
              label: Text(
                _qrImage == null ? 'إنشاء جلسة' : 'تحديث الكود',
                style: GoogleFonts.cairo(),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
              ),
            ),

            const SizedBox(height: 20),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '📋 الخطوات:',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text('1. افتح واتساب على هاتفك', style: GoogleFonts.cairo()),
                  Text('2. اذهب إلى ⋮ ← الأجهزة المرتبطة',
                      style: GoogleFonts.cairo()),
                  Text('3. اضغط "ربط جهاز"', style: GoogleFonts.cairo()),
                  Text('4. امسح الكود أعلاه', style: GoogleFonts.cairo()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServerSettingsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.dns, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  'إعدادات السيرفر',
                  style: GoogleFonts.cairo(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () =>
                      setState(() => _isEditingServer = !_isEditingServer),
                  icon: Icon(_isEditingServer ? Icons.close : Icons.edit),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_isEditingServer) ...[
              TextField(
                controller: _serverUrlController,
                decoration: const InputDecoration(
                  labelText: 'عنوان السيرفر',
                  hintText: 'http://xxx.xxx.xxx.xxx:3000',
                  prefixIcon: Icon(Icons.link),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: _saveServerUrl,
                child: Text('حفظ', style: GoogleFonts.cairo()),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.link, color: Colors.grey),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _serverUrlController.text,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.business, color: Colors.grey),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'معرف الشركة',
                          style: GoogleFonts.cairo(
                              fontSize: 12, color: Colors.grey[600]),
                        ),
                        Text(
                          widget.tenantId,
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBulkSettingsCard() {
    final delayInSeconds =
        _bulkDelayUnit == 'minutes' ? _bulkDelayValue * 60 : _bulkDelayValue;
    final sample100Time = (100 * delayInSeconds / 60).toStringAsFixed(1);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.purple.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child:
                      const Icon(Icons.schedule_send, color: Colors.purple),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'إعدادات الإرسال الجماعي',
                        style: GoogleFonts.cairo(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'الفاصل الزمني بين الرسائل لتجنب الحظر',
                        style: GoogleFonts.cairo(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // اختيار الوحدة
            Row(
              children: [
                Text('الوحدة:',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
                const SizedBox(width: 16),
                Expanded(
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'seconds',
                        label: Text('ثواني'),
                        icon: Icon(Icons.timer_outlined),
                      ),
                      ButtonSegment(
                        value: 'minutes',
                        label: Text('دقائق'),
                        icon: Icon(Icons.schedule),
                      ),
                    ],
                    selected: {_bulkDelayUnit},
                    onSelectionChanged: (value) {
                      setState(() {
                        _bulkDelayUnit = value.first;
                        if (_bulkDelayUnit == 'seconds') {
                          _bulkDelayValue = _bulkDelayValue.clamp(3, 60);
                        } else {
                          _bulkDelayValue = _bulkDelayValue.clamp(1, 10);
                        }
                      });
                    },
                    style: ButtonStyle(
                      backgroundColor:
                          WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.selected)) {
                          return Colors.purple.withOpacity(0.2);
                        }
                        return null;
                      }),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // التحكم بالقيمة
            Row(
              children: [
                IconButton(
                  onPressed: _canDecreaseBulkDelay()
                      ? () => setState(() => _bulkDelayValue--)
                      : null,
                  icon: const Icon(Icons.remove_circle_outline),
                  color: Colors.purple,
                  iconSize: 32,
                ),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.purple.shade200),
                    ),
                    child: Center(
                      child: Text(
                        '$_bulkDelayValue ${_bulkDelayUnit == 'seconds' ? 'ثانية' : 'دقيقة'}',
                        style: GoogleFonts.cairo(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.purple.shade800,
                        ),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _canIncreaseBulkDelay()
                      ? () => setState(() => _bulkDelayValue++)
                      : null,
                  icon: const Icon(Icons.add_circle_outline),
                  color: Colors.purple,
                  iconSize: 32,
                ),
              ],
            ),

            const SizedBox(height: 12),

            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: Colors.purple,
                inactiveTrackColor: Colors.purple.shade100,
                thumbColor: Colors.purple,
                overlayColor: Colors.purple.withOpacity(0.2),
              ),
              child: Slider(
                value: _bulkDelayValue.toDouble(),
                min: _bulkDelayUnit == 'seconds' ? 3 : 1,
                max: _bulkDelayUnit == 'seconds' ? 60 : 10,
                divisions: _bulkDelayUnit == 'seconds' ? 57 : 9,
                onChanged: (v) => setState(() => _bulkDelayValue = v.round()),
              ),
            ),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      color: Colors.blue.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'لإرسال 100 رسالة ≈ $sample100Time دقيقة',
                      style: GoogleFonts.cairo(
                        fontSize: 13,
                        color: Colors.blue.shade800,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _saveBulkSettings,
                icon: const Icon(Icons.save),
                label: Text(
                  'حفظ إعدادات الإرسال الجماعي',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageLogCard() {
    final dateFormat = intl.DateFormat('yyyy/MM/dd');
    final timeFormat = intl.DateFormat('HH:mm');
    final total = _logStats['total'] ?? 0;
    final success = _logStats['success'] ?? 0;
    final failed = _logStats['failed'] ?? 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // العنوان
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.teal.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.history, color: Colors.teal),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'سجل الرسائل المُرسلة',
                        style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'متابعة الرسائل المُرسلة عبر الواتساب',
                        style: GoogleFonts.cairo(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                // زر تحديث
                IconButton(
                  onPressed: _isLoadingLogs ? null : _loadMessageLogs,
                  icon: _isLoadingLogs
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh, size: 20),
                  tooltip: 'تحديث',
                ),
              ],
            ),
            const SizedBox(height: 16),

            // تصفية التاريخ
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Row(
                children: [
                  const Icon(Icons.date_range, size: 20, color: Colors.teal),
                  const SizedBox(width: 8),
                  Text('من:', style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _logFromDate ?? DateTime.now().subtract(const Duration(days: 7)),
                          firstDate: DateTime(2024),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          _logFromDate = picked;
                          _loadMessageLogs();
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: Text(
                          _logFromDate != null ? dateFormat.format(_logFromDate!) : 'الكل',
                          style: GoogleFonts.cairo(fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('إلى:', style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _logToDate ?? DateTime.now(),
                          firstDate: DateTime(2024),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          _logToDate = picked;
                          _loadMessageLogs();
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: Text(
                          _logToDate != null ? dateFormat.format(_logToDate!) : 'اليوم',
                          style: GoogleFonts.cairo(fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // زر مسح الفلاتر
                  if (_logFromDate != null || _logToDate != null)
                    IconButton(
                      onPressed: () {
                        _logFromDate = null;
                        _logToDate = null;
                        _loadMessageLogs();
                      },
                      icon: const Icon(Icons.clear, size: 18, color: Colors.red),
                      tooltip: 'مسح الفلتر',
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      padding: EdgeInsets.zero,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // فلاتر سريعة
            Wrap(
              spacing: 6,
              children: [
                _buildDateChip('اليوم', () {
                  _logFromDate = DateTime.now();
                  _logToDate = DateTime.now();
                  _loadMessageLogs();
                }),
                _buildDateChip('آخر 7 أيام', () {
                  _logFromDate = DateTime.now().subtract(const Duration(days: 7));
                  _logToDate = DateTime.now();
                  _loadMessageLogs();
                }),
                _buildDateChip('هذا الشهر', () {
                  final now = DateTime.now();
                  _logFromDate = DateTime(now.year, now.month, 1);
                  _logToDate = now;
                  _loadMessageLogs();
                }),
                _buildDateChip('الكل', () {
                  _logFromDate = null;
                  _logToDate = null;
                  _loadMessageLogs();
                }),
              ],
            ),
            const SizedBox(height: 16),

            // إحصائيات
            Row(
              children: [
                _buildStatBox('الكل', total, Colors.blue),
                const SizedBox(width: 8),
                _buildStatBox('ناجحة', success, Colors.green),
                const SizedBox(width: 8),
                _buildStatBox('فاشلة', failed, Colors.red),
                const SizedBox(width: 8),
                _buildStatBox('سيرفر', _logStats['server'] ?? 0, Colors.purple),
                const SizedBox(width: 8),
                _buildStatBox('تطبيق', _logStats['app'] ?? 0, Colors.orange),
              ],
            ),
            const SizedBox(height: 16),

            // قائمة الرسائل
            if (_logEntries.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                alignment: Alignment.center,
                child: Column(
                  children: [
                    Icon(Icons.inbox_outlined, size: 48, color: Colors.grey[300]),
                    const SizedBox(height: 8),
                    Text(
                      'لا توجد رسائل في هذه الفترة',
                      style: GoogleFonts.cairo(color: Colors.grey[500], fontSize: 14),
                    ),
                  ],
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 400),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _logEntries.length > 50 ? 50 : _logEntries.length,
                  separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey[200]),
                  itemBuilder: (context, index) {
                    final entry = _logEntries[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          // أيقونة الحالة
                          Container(
                            width: 32, height: 32,
                            decoration: BoxDecoration(
                              color: entry.success
                                  ? Colors.green.withValues(alpha: 0.1)
                                  : Colors.red.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              entry.success ? Icons.check : Icons.close,
                              size: 16,
                              color: entry.success ? Colors.green : Colors.red,
                            ),
                          ),
                          const SizedBox(width: 10),
                          // التفاصيل
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      entry.customerName.isNotEmpty ? entry.customerName : entry.phone,
                                      style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.w600),
                                    ),
                                    const Spacer(),
                                    Text(
                                      '${dateFormat.format(entry.timestamp)}  ${timeFormat.format(entry.timestamp)}',
                                      style: TextStyle(fontSize: 11, color: Colors.grey[500], fontFamily: 'monospace'),
                                    ),
                                  ],
                                ),
                                Row(
                                  children: [
                                    if (entry.customerName.isNotEmpty)
                                      Text(
                                        entry.phone,
                                        style: TextStyle(fontSize: 11, color: Colors.grey[600], fontFamily: 'monospace'),
                                      ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: _systemColor(entry.system).withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        _systemLabel(entry.system),
                                        style: TextStyle(fontSize: 10, color: _systemColor(entry.system), fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        _operationLabel(entry.operationType),
                                        style: TextStyle(fontSize: 10, color: Colors.grey[700]),
                                      ),
                                    ),
                                    if (entry.activatedBy != null && entry.activatedBy!.isNotEmpty) ...[
                                      const SizedBox(width: 4),
                                      Text(
                                        entry.activatedBy!,
                                        style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                                      ),
                                    ],
                                  ],
                                ),
                                if (entry.error != null)
                                  Text(
                                    entry.error!,
                                    style: const TextStyle(fontSize: 10, color: Colors.red),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

            if (_logEntries.length > 50)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'يتم عرض أحدث 50 رسالة من أصل ${_logEntries.length}',
                  style: GoogleFonts.cairo(fontSize: 11, color: Colors.grey[500]),
                  textAlign: TextAlign.center,
                ),
              ),

            // زر مسح السجل
            if (_logEntries.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text('مسح السجل', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                          content: Text('هل تريد مسح جميع سجلات الرسائل؟', style: GoogleFonts.cairo()),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('إلغاء', style: GoogleFonts.cairo())),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                              child: Text('مسح', style: GoogleFonts.cairo()),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        await WhatsAppMessageLogService.clearAll();
                        _loadMessageLogs();
                      }
                    },
                    icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                    label: Text('مسح السجل', style: GoogleFonts.cairo(fontSize: 12, color: Colors.red)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateChip(String label, VoidCallback onTap) {
    return ActionChip(
      label: Text(label, style: GoogleFonts.cairo(fontSize: 11)),
      onPressed: onTap,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      backgroundColor: Colors.teal.withValues(alpha: 0.08),
      side: BorderSide(color: Colors.teal.withValues(alpha: 0.2)),
    );
  }

  Widget _buildStatBox(String label, int count, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Text(
              '$count',
              style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.bold, color: color),
            ),
            Text(
              label,
              style: GoogleFonts.cairo(fontSize: 10, color: color),
            ),
          ],
        ),
      ),
    );
  }

  Color _systemColor(String system) {
    switch (system) {
      case 'server': return Colors.purple;
      case 'app': return Colors.orange;
      case 'web': return Colors.blue;
      case 'api': return Colors.teal;
      default: return Colors.grey;
    }
  }

  String _systemLabel(String system) {
    switch (system) {
      case 'server': return 'سيرفر';
      case 'app': return 'تطبيق';
      case 'web': return 'ويب';
      case 'api': return 'API';
      default: return system;
    }
  }

  String _operationLabel(String op) {
    switch (op) {
      case 'renewal': return 'تجديد';
      case 'bulk': return 'جماعي';
      case 'test': return 'تجريبي';
      case 'manual': return 'يدوي';
      default: return op;
    }
  }

  /// تحويل رقم محلي عراقي إلى صيغة دولية
  String _formatPhoneToInternational(String phone) {
    final clean = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (clean.startsWith('964')) return clean;
    if (clean.startsWith('0')) return '964${clean.substring(1)}';
    return '964$clean';
  }

  Widget _buildInfoCard() {
    return Card(
      color: Colors.amber[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.amber),
                const SizedBox(width: 8),
                Text(
                  'معلومات مهمة',
                  style: GoogleFonts.cairo(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text('• يجب أن يكون الهاتف متصلاً بالإنترنت',
                style: GoogleFonts.cairo(fontSize: 14)),
            Text('• الحد الأقصى ~500 رسالة يومياً',
                style: GoogleFonts.cairo(fontSize: 14)),
            Text('• تأخير 2-3 ثواني بين الرسائل لتجنب الحظر',
                style: GoogleFonts.cairo(fontSize: 14)),
            Text('• الجلسة تبقى نشطة حتى قطع الاتصال يدوياً',
                style: GoogleFonts.cairo(fontSize: 14)),
          ],
        ),
      ),
    );
  }

  bool _canDecreaseBulkDelay() {
    return _bulkDelayUnit == 'seconds'
        ? _bulkDelayValue > 3
        : _bulkDelayValue > 1;
  }

  bool _canIncreaseBulkDelay() {
    return _bulkDelayUnit == 'seconds'
        ? _bulkDelayValue < 60
        : _bulkDelayValue < 10;
  }

  Future<void> _saveBulkSettings() async {
    final success = await WhatsAppServerService.saveBulkSettings(
      delayValue: _bulkDelayValue,
      delayUnit: _bulkDelayUnit,
      tenantId: widget.tenantId,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? '✅ تم حفظ إعدادات الإرسال الجماعي'
                : '❌ فشل في حفظ الإعدادات',
          ),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }
}
