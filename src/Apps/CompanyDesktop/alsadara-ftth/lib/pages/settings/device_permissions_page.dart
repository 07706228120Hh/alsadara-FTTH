/// صفحة إدارة صلاحيات الأجهزة للتخزين المحلي
/// تتيح للمدير إدارة الأجهزة المعتمدة وتوليد أكواد التفعيل
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/device_registration_service.dart';

class DevicePermissionsPage extends StatefulWidget {
  const DevicePermissionsPage({super.key});

  @override
  State<DevicePermissionsPage> createState() => _DevicePermissionsPageState();
}

class _DevicePermissionsPageState extends State<DevicePermissionsPage> {
  List<RegisteredDevice> _devices = [];
  bool _isLoading = true;
  String? _currentDeviceId;

  // للكود المولّد
  ActivationCode? _generatedCode;
  Timer? _codeTimer;
  int _remainingSeconds = 0;

  @override
  void initState() {
    super.initState();
    _loadDevices();
    _getCurrentDeviceId();
    // تنظيف الأكواد المنتهية عند فتح الصفحة
    _cleanupCodes();
  }

  Future<void> _cleanupCodes() async {
    try {
      await DeviceRegistrationService.cleanupExpiredCodes();
    } catch (e) {
      debugPrint('⚠️ خطأ في تنظيف الأكواد');
    }
  }

  @override
  void dispose() {
    _codeTimer?.cancel();
    super.dispose();
  }

  Future<void> _getCurrentDeviceId() async {
    try {
      final id = await DeviceRegistrationService.getDeviceId();
      if (mounted) {
        setState(() => _currentDeviceId = id);
      }
    } catch (e) {
      debugPrint('⚠️ خطأ في جلب معرف الجهاز');
    }
  }

  Future<void> _loadDevices() async {
    setState(() => _isLoading = true);
    try {
      final devices = await DeviceRegistrationService.getApprovedDevices();
      if (mounted) {
        setState(() {
          _devices = devices;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showError('فشل في تحميل الأجهزة');
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, textAlign: TextAlign.right),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, textAlign: TextAlign.right),
        backgroundColor: Colors.green,
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // توليد كود التفعيل
  // ═══════════════════════════════════════════════════════════

  Future<void> _generateCode() async {
    final code = await DeviceRegistrationService.generateActivationCode(
      validMinutes: 10,
    );

    if (code != null && mounted) {
      setState(() {
        _generatedCode = code;
        _remainingSeconds = code.remainingTime.inSeconds;
      });

      // بدء العداد
      _codeTimer?.cancel();
      _codeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_remainingSeconds > 0) {
          setState(() => _remainingSeconds--);
        } else {
          timer.cancel();
          setState(() => _generatedCode = null);
        }
      });

      _showGeneratedCodeDialog();
    } else {
      _showError('فشل في توليد الكود');
    }
  }

  void _showGeneratedCodeDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          // تحديث العداد في الـ dialog
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted && _generatedCode != null && _remainingSeconds > 0) {
              setDialogState(() {});
            }
          });

          return AlertDialog(
            title: const Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('كود تفعيل جديد'),
                SizedBox(width: 8),
                Icon(Icons.key, color: Colors.orange),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'شارك هذا الكود مع المستخدم لتسجيل جهازه',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.copy, color: Colors.blue),
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(text: _generatedCode?.code ?? ''),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('تم نسخ الكود'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        },
                        tooltip: 'نسخ',
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _generatedCode?.code ?? '',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 8,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.timer,
                      size: 16,
                      color: _remainingSeconds < 60 ? Colors.red : Colors.grey,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'صالح لمدة ${_formatTime(_remainingSeconds)}',
                      style: TextStyle(
                        color:
                            _remainingSeconds < 60 ? Colors.red : Colors.grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إغلاق'),
              ),
            ],
          );
        },
      ),
    );
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    if (minutes > 0) {
      return '$minutes:${secs.toString().padLeft(2, '0')}';
    }
    return '$secs ثانية';
  }

  // ═══════════════════════════════════════════════════════════
  // تفعيل جهاز بكود
  // ═══════════════════════════════════════════════════════════

  void _showActivateDeviceDialog() {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('تسجيل هذا الجهاز'),
            SizedBox(width: 8),
            Icon(Icons.add_circle, color: Colors.green),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'أدخل كود التفعيل المكون من 6 أرقام',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              maxLength: 6,
              style: const TextStyle(
                fontSize: 24,
                letterSpacing: 8,
                fontWeight: FontWeight.bold,
              ),
              decoration: InputDecoration(
                hintText: '000000',
                counterText: '',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              final code = controller.text.trim();
              if (code.length != 6) {
                _showError('الكود يجب أن يكون 6 أرقام');
                return;
              }

              Navigator.pop(ctx);

              try {
                final result =
                    await DeviceRegistrationService.activateDeviceWithCode(
                        code);
                if (mounted) {
                  if (result.success) {
                    _showSuccess(result.message);
                    _loadDevices();
                  } else {
                    _showError(result.message);
                  }
                }
              } catch (e) {
                if (mounted) {
                  _showError('حدث خطأ');
                }
              }
            },
            child: const Text('تفعيل'),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // إجراءات على الأجهزة
  // ═══════════════════════════════════════════════════════════

  Future<void> _toggleDeviceStatus(RegisteredDevice device) async {
    final action = device.isActive ? 'إلغاء تفعيل' : 'إعادة تفعيل';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$action الجهاز؟'),
        content: Text('هل تريد $action "${device.deviceName}"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: device.isActive ? Colors.orange : Colors.green,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    );

    if (confirm == true) {
      bool success;
      if (device.isActive) {
        success = await DeviceRegistrationService.revokeDevice(device.deviceId);
      } else {
        success =
            await DeviceRegistrationService.reactivateDevice(device.deviceId);
      }

      if (success) {
        _showSuccess('تم $action الجهاز بنجاح');
        _loadDevices();
      } else {
        _showError('فشل في $action الجهاز');
      }
    }
  }

  Future<void> _deleteDevice(RegisteredDevice device) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('حذف الجهاز'),
            SizedBox(width: 8),
            Icon(Icons.delete_forever, color: Colors.red),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('هل تريد حذف "${device.deviceName}" نهائياً؟'),
            const SizedBox(height: 8),
            const Text(
              'سيحتاج المستخدم لكود تفعيل جديد لإعادة تسجيل الجهاز',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success =
          await DeviceRegistrationService.deleteDevice(device.deviceId);
      if (success) {
        _showSuccess('تم حذف الجهاز');
        _loadDevices();
      } else {
        _showError('فشل في حذف الجهاز');
      }
    }
  }

  // ═══════════════════════════════════════════════════════════
  // البناء
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'صلاحيات الأجهزة',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
          backgroundColor: const Color(0xFF1E3A5F),
          foregroundColor: Colors.white,
          elevation: 2,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadDevices,
              tooltip: 'تحديث',
            ),
          ],
        ),
        body: Column(
          children: [
            // الإجراءات السريعة
            _buildActionsCard(),

            // قائمة الأجهزة
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _devices.isEmpty
                      ? _buildEmptyState()
                      : _buildDevicesList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionsCard() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.blue, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'الأجهزة المعتمدة فقط يمكنها تخزين بيانات المشتركين محلياً',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _generateCode,
                    icon: const Icon(Icons.key),
                    label: const Text('توليد كود تفعيل'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _showActivateDeviceDialog,
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('تسجيل هذا الجهاز'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.devices_other, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'لا توجد أجهزة مسجلة',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'ولّد كود تفعيل لتسجيل جهاز جديد',
            style: TextStyle(color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }

  Widget _buildDevicesList() {
    final activeDevices = _devices.where((d) => d.isActive).toList();
    final inactiveDevices = _devices.where((d) => !d.isActive).toList();

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        // الأجهزة النشطة
        if (activeDevices.isNotEmpty) ...[
          _buildSectionHeader(
            'الأجهزة النشطة',
            Icons.check_circle,
            Colors.green,
            activeDevices.length,
          ),
          ...activeDevices.map((d) => _buildDeviceCard(d)),
        ],

        // الأجهزة الموقوفة
        if (inactiveDevices.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildSectionHeader(
            'الأجهزة الموقوفة',
            Icons.block,
            Colors.grey,
            inactiveDevices.length,
          ),
          ...inactiveDevices.map((d) => _buildDeviceCard(d)),
        ],

        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildSectionHeader(
      String title, IconData icon, Color color, int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceCard(RegisteredDevice device) {
    final isCurrentDevice = device.deviceId == _currentDeviceId;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isCurrentDevice
            ? const BorderSide(color: Colors.blue, width: 2)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // أيقونة الجهاز
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: device.isActive
                    ? Colors.green.withValues(alpha: 0.1)
                    : Colors.grey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  device.platformIcon,
                  style: const TextStyle(fontSize: 24),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // معلومات الجهاز
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          device.deviceName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isCurrentDevice)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'هذا الجهاز',
                            style: TextStyle(
                              color: Colors.blue,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${device.platformName} • سجله: ${device.registeredByName}',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    'آخر استخدام: ${_formatDate(device.lastUsed ?? device.registeredAt)}',
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),

            // أزرار الإجراءات
            Column(
              children: [
                IconButton(
                  icon: Icon(
                    device.isActive ? Icons.block : Icons.check_circle,
                    color: device.isActive ? Colors.orange : Colors.green,
                    size: 20,
                  ),
                  onPressed: () => _toggleDeviceStatus(device),
                  tooltip: device.isActive ? 'إيقاف' : 'تفعيل',
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                  onPressed: () => _deleteDevice(device),
                  tooltip: 'حذف',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} دقيقة';
    if (diff.inHours < 24) return 'منذ ${diff.inHours} ساعة';
    if (diff.inDays < 7) return 'منذ ${diff.inDays} يوم';

    return '${date.day}/${date.month}/${date.year}';
  }
}
