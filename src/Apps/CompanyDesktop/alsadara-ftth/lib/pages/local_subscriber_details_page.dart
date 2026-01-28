/// صفحة تفاصيل المشترك المحلي
/// تعرض جميع معلومات المشترك المخزنة محلياً
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/local_database_service.dart';

class LocalSubscriberDetailsPage extends StatefulWidget {
  final Map<String, dynamic> subscriber;

  const LocalSubscriberDetailsPage({
    super.key,
    required this.subscriber,
  });

  @override
  State<LocalSubscriberDetailsPage> createState() =>
      _LocalSubscriberDetailsPageState();
}

class _LocalSubscriberDetailsPageState
    extends State<LocalSubscriberDetailsPage> {
  final LocalDatabaseService _db = LocalDatabaseService.instance;

  String? _phoneNumber;
  List<Map<String, dynamic>> _addresses = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAdditionalData();
  }

  Future<void> _loadAdditionalData() async {
    final subscriptionId = widget.subscriber['subscription_id']?.toString() ??
        widget.subscriber['customer_id']?.toString() ??
        '';

    if (subscriptionId.isNotEmpty) {
      // جلب رقم الهاتف
      final phone = await _db.getUserPhone(subscriptionId);

      // جلب العناوين
      final addresses = await _db.getAddressesForCustomer(subscriptionId);

      setState(() {
        _phoneNumber = phone;
        _addresses = addresses;
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('تم نسخ $label'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'active':
        return Colors.green;
      case 'inactive':
        return Colors.orange;
      case 'expired':
        return Colors.red;
      case 'suspended':
        return Colors.grey;
      default:
        return Colors.blue;
    }
  }

  String _getStatusName(String? status) {
    switch (status?.toLowerCase()) {
      case 'active':
        return 'نشط';
      case 'inactive':
        return 'غير نشط';
      case 'expired':
        return 'منتهي';
      case 'suspended':
        return 'موقوف';
      default:
        return status ?? 'غير معروف';
    }
  }

  @override
  Widget build(BuildContext context) {
    final sub = widget.subscriber;
    final displayName = sub['display_name'] ?? sub['username'] ?? 'غير معروف';
    final status = sub['status']?.toString();

    return Scaffold(
      appBar: AppBar(
        title: Text(displayName),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_all),
            onPressed: () => _copyAllInfo(),
            tooltip: 'نسخ الكل',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // بطاقة الهوية
                  _buildHeaderCard(displayName, status),
                  const SizedBox(height: 16),

                  // معلومات الاشتراك
                  _buildSubscriptionCard(),
                  const SizedBox(height: 16),

                  // الشريك
                  _buildPartnerCard(),
                  const SizedBox(height: 16),

                  // معلومات الجهاز
                  _buildDeviceCard(),
                  const SizedBox(height: 16),

                  // معلومات الهوية
                  _buildIdentityCard(),
                  const SizedBox(height: 16),

                  // حالات خاصة
                  _buildStatusCard(),
                  const SizedBox(height: 16),

                  // العناوين
                  if (_addresses.isNotEmpty) ...[
                    _buildAddressesCard(),
                    const SizedBox(height: 16),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildHeaderCard(String name, String? status) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [
              _getStatusColor(status),
              _getStatusColor(status).withValues(alpha: 0.7),
            ],
          ),
        ),
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            CircleAvatar(
              radius: 35,
              backgroundColor: Colors.white,
              child: Icon(
                Icons.person,
                size: 40,
                color: _getStatusColor(status),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _getStatusName(status),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
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

  Widget _buildSubscriptionCard() {
    final sub = widget.subscriber;
    final subscriptionId = sub['subscription_id']?.toString() ?? '-';
    final customerId = sub['customer_id']?.toString() ?? '';
    final phone = sub['phone']?.toString() ?? _phoneNumber ?? '';

    return _buildInfoCard(
      title: 'معلومات الاشتراك',
      icon: Icons.card_membership,
      children: [
        // رقم الهاتف أولاً
        _buildInfoRow(
          'رقم الهاتف',
          phone.isNotEmpty ? phone : 'غير متوفر',
          canCopy: phone.isNotEmpty,
          icon: Icons.phone,
        ),
        // معرف العميل
        _buildInfoRow(
          'معرف العميل',
          customerId.isNotEmpty ? customerId : '-',
          canCopy: customerId.isNotEmpty,
          icon: Icons.person,
        ),
        _buildInfoRow(
          'معرف الاشتراك',
          subscriptionId,
          canCopy: true,
        ),
        _buildInfoRow(
          'اسم المستخدم',
          sub['username']?.toString() ?? '-',
          canCopy: true,
        ),
        _buildInfoRow(
          'الحالة',
          _getStatusName(sub['status']?.toString()),
          valueColor: _getStatusColor(sub['status']?.toString()),
        ),
        _buildInfoRow(
          'الحزمة',
          sub['bundle_name']?.toString() ?? sub['bundle_id']?.toString() ?? '-',
        ),
        _buildInfoRow(
          'الباقة',
          sub['profile_name']?.toString() ?? '-',
        ),
        _buildInfoRow(
          'التجديد التلقائي',
          sub['auto_renew'] == true ? 'نعم' : 'لا',
        ),
        _buildInfoRow(
          'تاريخ البدء',
          _formatDate(sub['started_at']),
        ),
        _buildInfoRow(
          'تاريخ الانتهاء',
          _formatDate(sub['expires']),
          valueColor: _getExpiryColor(sub['expires']),
        ),
        _buildInfoRow(
          'فترة الالتزام',
          '${sub['commitment_period'] ?? '-'} شهر',
        ),
      ],
    );
  }

  Widget _buildServicesCard() {
    final services = widget.subscriber['services'] as List? ?? [];
    if (services.isEmpty) return const SizedBox.shrink();

    return _buildInfoCard(
      title: 'الخدمات (${services.length})',
      icon: Icons.miscellaneous_services,
      children: [
        ...services.map((service) {
          final svc = service as Map<String, dynamic>;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: svc['type'] == 'Base'
                        ? Colors.blue.shade100
                        : Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    svc['displayValue']?.toString() ??
                        svc['id']?.toString() ??
                        '-',
                    style: TextStyle(
                      color: svc['type'] == 'Base'
                          ? Colors.blue.shade900
                          : Colors.orange.shade900,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '(${svc['type'] ?? ''})',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildPartnerCard() {
    final sub = widget.subscriber;
    final partnerId = sub['partner_id']?.toString() ?? '';
    final partnerName = sub['partner_name']?.toString() ?? '';

    if (partnerId.isEmpty && partnerName.isEmpty) {
      return const SizedBox.shrink();
    }

    return _buildInfoCard(
      title: 'الشريك',
      icon: Icons.business,
      children: [
        _buildInfoRow(
          'اسم الشريك',
          partnerName.isNotEmpty ? partnerName : '-',
        ),
        _buildInfoRow(
          'معرف الشريك',
          partnerId.isNotEmpty ? partnerId : '-',
          canCopy: partnerId.isNotEmpty,
        ),
      ],
    );
  }

  // تم حذف _buildConnectionCard - لم تعد هناك حاجة لعرض IP و MAC

  Widget _buildContactCard() {
    final sub = widget.subscriber;
    final phone = sub['phone']?.toString() ?? _phoneNumber ?? '';

    return _buildInfoCard(
      title: 'معلومات التواصل',
      icon: Icons.contact_phone,
      children: [
        _buildInfoRow(
          'رقم الهاتف',
          phone.isNotEmpty ? phone : 'غير متوفر',
          canCopy: phone.isNotEmpty,
        ),
        _buildInfoRow(
          'البريد الإلكتروني',
          sub['email']?.toString().isNotEmpty == true
              ? sub['email'].toString()
              : 'غير متوفر',
          canCopy: sub['email']?.toString().isNotEmpty == true,
        ),
        _buildInfoRow(
          'هاتف ثانوي',
          sub['secondary_phone']?.toString().isNotEmpty == true
              ? sub['secondary_phone'].toString()
              : 'غير متوفر',
          canCopy: sub['secondary_phone']?.toString().isNotEmpty == true,
        ),
      ],
    );
  }

  Widget _buildZoneCard() {
    final sub = widget.subscriber;

    return _buildInfoCard(
      title: 'معلومات المنطقة',
      icon: Icons.location_on,
      children: [
        _buildInfoRow(
          'المنطقة',
          sub['zone_name']?.toString() ?? '-',
        ),
        _buildInfoRow(
          'معرف المنطقة',
          sub['zone_id']?.toString() ?? '-',
          canCopy: true,
        ),
        _buildInfoRow(
          'خط العمل',
          sub['line_of_business']?.toString() ?? '-',
        ),
      ],
    );
  }

  Widget _buildDeviceCard() {
    final sub = widget.subscriber;
    final hasDeviceInfo = sub['device_serial']?.toString().isNotEmpty == true ||
        sub['fdt_name']?.toString().isNotEmpty == true ||
        sub['fat_name']?.toString().isNotEmpty == true;

    if (!hasDeviceInfo) return const SizedBox.shrink();

    return _buildInfoCard(
      title: 'معلومات الجهاز',
      icon: Icons.router,
      children: [
        _buildInfoRow(
          'الرقم التسلسلي',
          sub['device_serial']?.toString() ?? '-',
          canCopy: true,
        ),
        _buildInfoRow(
          'FDT',
          sub['fdt_name']?.toString() ?? '-',
        ),
        _buildInfoRow(
          'FAT',
          sub['fat_name']?.toString() ?? '-',
        ),
      ],
    );
  }

  // تم حذف بطاقة الجلسة النشطة

  Widget _buildIdentityCard() {
    final sub = widget.subscriber;
    final hasIdentity =
        sub['national_id_number']?.toString().isNotEmpty == true ||
            sub['mother_name']?.toString().isNotEmpty == true;

    if (!hasIdentity) return const SizedBox.shrink();

    return _buildInfoCard(
      title: 'معلومات الهوية',
      icon: Icons.badge,
      children: [
        if (sub['mother_name']?.toString().isNotEmpty == true)
          _buildInfoRow(
            'اسم الأم',
            sub['mother_name'].toString(),
          ),
        if (sub['national_id_number']?.toString().isNotEmpty == true)
          _buildInfoRow(
            'رقم الهوية',
            sub['national_id_number'].toString(),
            canCopy: true,
          ),
        if (sub['national_id_family_number']?.toString().isNotEmpty == true)
          _buildInfoRow(
            'رقم العائلة',
            sub['national_id_family_number'].toString(),
            canCopy: true,
          ),
        if (sub['national_id_place']?.toString().isNotEmpty == true)
          _buildInfoRow(
            'مكان الإصدار',
            sub['national_id_place'].toString(),
          ),
        if (sub['national_id_date']?.toString().isNotEmpty == true)
          _buildInfoRow(
            'تاريخ الإصدار',
            _formatDate(sub['national_id_date']),
          ),
        if (sub['customer_type']?.toString().isNotEmpty == true)
          _buildInfoRow(
            'نوع العميل',
            sub['customer_type'].toString(),
          ),
        if (sub['referral_code']?.toString().isNotEmpty == true)
          _buildInfoRow(
            'كود الإحالة',
            sub['referral_code'].toString(),
            canCopy: true,
          ),
      ],
    );
  }

  Widget _buildDetailedAddressCard() {
    final sub = widget.subscriber;
    final hasGps = sub['gps_lat']?.toString().isNotEmpty == true &&
        sub['gps_lng']?.toString().isNotEmpty == true;

    if (!hasGps) return const SizedBox.shrink();

    return _buildInfoCard(
      title: 'الإحداثيات',
      icon: Icons.location_on,
      children: [
        _buildInfoRow(
          'الإحداثيات',
          '${sub['gps_lat']}, ${sub['gps_lng']}',
          canCopy: true,
        ),
        if (sub['apartment']?.toString().isNotEmpty == true)
          _buildInfoRow(
            'الشقة',
            sub['apartment'].toString(),
          ),
        if (sub['nearest_point']?.toString().isNotEmpty == true)
          _buildInfoRow(
            'أقرب نقطة',
            sub['nearest_point'].toString(),
          ),
      ],
    );
  }

  String _formatDateTime(dynamic dateTime) {
    if (dateTime == null) return '-';
    final dateStr = dateTime.toString();
    if (dateStr.isEmpty) return '-';

    try {
      final dt = DateTime.parse(dateStr);
      return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return dateStr;
    }
  }

  String _formatSessionTime(dynamic seconds) {
    if (seconds == null) return '-';
    try {
      final secs = int.parse(seconds.toString());
      final hours = secs ~/ 3600;
      final minutes = (secs % 3600) ~/ 60;
      if (hours > 0) {
        return '$hours ساعة و $minutes دقيقة';
      }
      return '$minutes دقيقة';
    } catch (e) {
      return seconds.toString();
    }
  }

  Widget _buildStatusCard() {
    final sub = widget.subscriber;

    return _buildInfoCard(
      title: 'حالات خاصة',
      icon: Icons.warning_amber,
      children: [
        _buildInfoRow(
          'موقوف',
          sub['is_suspended'] == true ? 'نعم' : 'لا',
          valueColor: sub['is_suspended'] == true ? Colors.red : Colors.green,
        ),
        if (sub['is_suspended'] == true &&
            sub['suspension_reason']?.toString().isNotEmpty == true)
          _buildInfoRow(
            'سبب الإيقاف',
            sub['suspension_reason'].toString(),
          ),
        _buildInfoRow(
          'مبني على الكوتا',
          sub['is_quota_based'] == true ? 'نعم' : 'لا',
        ),
        if (sub['is_quota_based'] == true &&
            sub['total_quota_in_bytes']?.toString().isNotEmpty == true)
          _buildInfoRow(
            'إجمالي الكوتا',
            _formatBytes(sub['total_quota_in_bytes']),
          ),
        _buildInfoRow(
          'تجريبي',
          sub['is_trial'] == true ? 'نعم' : 'لا',
          valueColor: sub['is_trial'] == true ? Colors.orange : null,
        ),
        _buildInfoRow(
          'معلق',
          sub['is_pending'] == true ? 'نعم' : 'لا',
          valueColor: sub['is_pending'] == true ? Colors.orange : null,
        ),
        if (sub['has_different_billing'] == true)
          _buildInfoRow(
            'فوترة مختلفة',
            'نعم',
            valueColor: Colors.purple,
          ),
      ],
    );
  }

  Widget _buildAddressesCard() {
    return _buildInfoCard(
      title: 'العناوين (${_addresses.length})',
      icon: Icons.home,
      children: [
        ..._addresses.asMap().entries.map((entry) {
          final index = entry.key;
          final address = entry.value;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (index > 0) const Divider(),
              _buildInfoRow(
                'العنوان ${index + 1}',
                address['full_address']?.toString() ?? '-',
              ),
              _buildInfoRow(
                'المنطقة',
                address['zone_name']?.toString() ?? '-',
              ),
              _buildInfoRow(
                'FAT',
                address['fat_name']?.toString() ?? '-',
              ),
              if (address['gps_lat'] != null &&
                  address['gps_lat'].toString().isNotEmpty)
                _buildInfoRow(
                  'الإحداثيات',
                  '${address['gps_lat']}, ${address['gps_lng']}',
                  canCopy: true,
                ),
            ],
          );
        }),
      ],
    );
  }

  Widget _buildAdditionalInfoCard() {
    final sub = widget.subscriber;

    return _buildInfoCard(
      title: 'معلومات إضافية',
      icon: Icons.info_outline,
      children: [
        _buildInfoRow(
          'وصف الاشتراك',
          sub['self_display_value']?.toString() ?? '-',
        ),
        _buildInfoRow(
          'الاسم الأول',
          sub['first_name']?.toString().isNotEmpty == true
              ? sub['first_name'].toString()
              : '-',
        ),
        _buildInfoRow(
          'الاسم الأخير',
          sub['last_name']?.toString().isNotEmpty == true
              ? sub['last_name'].toString()
              : '-',
        ),
        _buildInfoRow(
          'تاريخ المزامنة',
          _formatDate(sub['synced_at']),
        ),
      ],
    );
  }

  String _formatBytes(dynamic bytes) {
    if (bytes == null || bytes.toString().isEmpty) return '-';
    try {
      final b = double.parse(bytes.toString());
      if (b >= 1073741824) return '${(b / 1073741824).toStringAsFixed(2)} GB';
      if (b >= 1048576) return '${(b / 1048576).toStringAsFixed(2)} MB';
      if (b >= 1024) return '${(b / 1024).toStringAsFixed(2)} KB';
      return '${b.toInt()} B';
    } catch (_) {
      return bytes.toString();
    }
  }

  Widget _buildInfoCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: const Color(0xFF1A237E)),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    String label,
    String value, {
    bool canCopy = false,
    Color? valueColor,
    IconData? icon,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: Colors.grey[600]),
            const SizedBox(width: 8),
          ],
          SizedBox(
            width: icon != null ? 94 : 120,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: valueColor,
                    ),
                  ),
                ),
                if (canCopy &&
                    value != '-' &&
                    value.isNotEmpty &&
                    value != 'غير متوفر')
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: () => _copyToClipboard(value, label),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    color: Colors.grey[600],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatSpeed(dynamic speed) {
    if (speed == null) return '-';
    final speedStr = speed.toString();
    if (speedStr.isEmpty) return '-';

    // إذا كانت السرعة بالـ Kbps، حولها إلى Mbps
    final speedNum = double.tryParse(speedStr);
    if (speedNum != null) {
      if (speedNum >= 1000) {
        return '${(speedNum / 1000).toStringAsFixed(0)} Mbps';
      }
      return '$speedNum Kbps';
    }
    return speedStr;
  }

  String _formatDate(dynamic date) {
    if (date == null) return '-';
    final dateStr = date.toString();
    if (dateStr.isEmpty) return '-';

    try {
      final dateTime = DateTime.parse(dateStr);
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    } catch (e) {
      return dateStr;
    }
  }

  Color? _getExpiryColor(dynamic expires) {
    if (expires == null) return null;

    try {
      final date = DateTime.parse(expires.toString());
      final now = DateTime.now();
      final diff = date.difference(now);

      if (diff.isNegative) {
        return Colors.red;
      } else if (diff.inDays <= 7) {
        return Colors.orange;
      }
      return Colors.green;
    } catch (e) {
      return null;
    }
  }

  void _copyAllInfo() {
    final sub = widget.subscriber;
    final buffer = StringBuffer();

    buffer.writeln('معلومات المشترك');
    buffer.writeln('================');
    buffer.writeln('الاسم: ${sub['display_name'] ?? sub['username'] ?? '-'}');
    buffer.writeln('معرف العميل: ${sub['customer_id'] ?? '-'}');
    buffer.writeln('اسم المستخدم: ${sub['username'] ?? '-'}');
    buffer.writeln('الحالة: ${_getStatusName(sub['status']?.toString())}');
    buffer.writeln('الباقة: ${sub['profile_name'] ?? '-'}');
    buffer.writeln('تاريخ الانتهاء: ${_formatDate(sub['expires'])}');
    buffer.writeln('المنطقة: ${sub['zone_name'] ?? '-'}');

    if (_phoneNumber != null) {
      buffer.writeln('رقم الهاتف: $_phoneNumber');
    }

    if (_addresses.isNotEmpty) {
      buffer.writeln('\nالعناوين:');
      for (var i = 0; i < _addresses.length; i++) {
        final addr = _addresses[i];
        buffer.writeln('  ${i + 1}. ${addr['full_address'] ?? '-'}');
        buffer.writeln('     FAT: ${addr['fat_name'] ?? '-'}');
      }
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم نسخ جميع المعلومات'),
        backgroundColor: Colors.green,
      ),
    );
  }
}
