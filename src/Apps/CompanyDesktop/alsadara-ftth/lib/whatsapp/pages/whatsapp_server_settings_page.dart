/// صفحة إعدادات WhatsApp Server
/// ربط رقم الشركة عبر QR Code
/// عرض حالة الاتصال وإرسال تجريبي
library;

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/whatsapp_server_service.dart';

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

    setState(() => _isLoading = false);
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
                '⚠️ انقطع اتصال الواتساب — يرجى مسح QR جديد',
                style: const TextStyle(fontFamily: 'Cairo'),
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 5),
            ),
          );
        }
        // إنشاء جلسة جديدة تلقائياً
        await _createSession();
        return;
      }

      if (!_isConnected && !_isLoadingQR) {
        // إذا لا يوجد QR أو انتهت صلاحيته → أنشئ جلسة جديدة
        if (_qrImage == null || _isQRExpired()) {
          await _createSession();
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
                '⚠️ انقطع اتصال الواتساب — يتم إنشاء جلسة جديدة...',
                style: const TextStyle(fontFamily: 'Cairo'),
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 5),
            ),
          );
          await _createSession();
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
    });

    await WhatsAppServerService.createSession(widget.tenantId);
    await Future.delayed(const Duration(seconds: 3));

    final qr = await WhatsAppServerService.getQRImage(widget.tenantId);

    if (mounted) {
      setState(() {
        _qrImage = qr;
        _lastQRFetch = qr != null ? DateTime.now() : null;
        _isLoadingQR = false;
      });

      if (qr != null) {
        _startConnectionMonitor();
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

    final phone = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إرسال رسالة تجريبية'),
        content: TextField(
          controller: phoneController,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'رقم الهاتف',
            hintText: '07xxxxxxxxx',
            prefixIcon: Icon(Icons.phone),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, phoneController.text),
            child: const Text('إرسال'),
          ),
        ],
      ),
    );

    if (phone == null || phone.isEmpty) return;

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text('جاري الإرسال...'),
          ],
        ),
      ),
    );

    final error = await WhatsAppServerService.sendMessageWithError(
      tenantId: widget.tenantId,
      phone: phone,
      message:
          '🎉 رسالة تجريبية من نظام إدارة الاشتراكات!\n\nتم إرسال هذه الرسالة تلقائياً للتأكد من عمل النظام.',
    );

    if (mounted) Navigator.pop(context);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error == null
                ? '✅ تم إرسال الرسالة بنجاح!'
                : '❌ فشل الإرسال: $error',
          ),
          backgroundColor: error == null ? Colors.green : Colors.red,
          duration: const Duration(seconds: 8),
        ),
      );
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
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: _isServerOnline
                    ? Colors.green.withOpacity(0.1)
                    : Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _isServerOnline ? Icons.cloud_done : Icons.cloud_off,
                color: _isServerOnline ? Colors.green : Colors.red,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'حالة السيرفر',
                    style: GoogleFonts.cairo(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                  Text(
                    _isServerOnline ? 'متصل ✅' : 'غير متصل ❌',
                    style: GoogleFonts.cairo(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _isServerOnline ? Colors.green : Colors.red,
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
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: _sendTestMessage,
                  icon: const Icon(Icons.send),
                  label: Text('إرسال تجريبي', style: GoogleFonts.cairo()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: _disconnect,
                  icon: const Icon(Icons.link_off, color: Colors.red),
                  label: Text('قطع الاتصال',
                      style: GoogleFonts.cairo(color: Colors.red)),
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
              const SizedBox(
                width: 250,
                height: 250,
                child: Center(child: CircularProgressIndicator()),
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
