import 'package:flutter/material.dart';
import '../services/whatsapp_bulk_sender_service.dart';
import '../services/whatsapp_business_service.dart';
import 'whatsapp_batch_reports_page.dart';
import 'whatsapp_business_config_page.dart';

/// صفحة إرسال رسائل WhatsApp جماعية
class WhatsAppBulkSenderPage extends StatefulWidget {
  const WhatsAppBulkSenderPage({super.key});

  @override
  State<WhatsAppBulkSenderPage> createState() => _WhatsAppBulkSenderPageState();
}

class _WhatsAppBulkSenderPageState extends State<WhatsAppBulkSenderPage> {
  final _offerTextController = TextEditingController(
    text: 'باقة FIBER 35 بسعر 30,000 د.ع فقط!',
  );

  bool _isSending = false;
  bool _isConfigured = false;
  bool _isWebhookConfigured = false;
  Map<String, dynamic>? _lastResult;

  // نوع القالب المحدد
  String _selectedTemplateType = 'sadara_reminder';

  // أنواع القوالب المتاحة
  final List<Map<String, dynamic>> _templateTypes = [
    {
      'value': 'sadara_reminder',
      'label': '⚠️ تذكير قبل الانتهاء',
      'description': 'للمشتركين الذين سينتهي اشتراكهم قريباً',
      'icon': Icons.warning_amber_rounded,
      'color': Colors.orange,
    },
    {
      'value': 'sadara_renewed',
      'label': '✅ تم التجديد',
      'description': 'إشعار بعد تجديد الاشتراك بنجاح',
      'icon': Icons.check_circle_rounded,
      'color': Colors.green,
    },
    {
      'value': 'sadara_expired',
      'label': '📢 اشتراك منتهي + عرض',
      'description': 'للمشتركين المنتهية اشتراكاتهم مع عرض خاص',
      'icon': Icons.campaign_rounded,
      'color': Colors.red,
    },
  ];

  // قائمة المستلمين
  final List<Map<String, dynamic>> _recipients = [];

  @override
  void initState() {
    super.initState();
    _checkConfiguration();
  }

  Future<void> _checkConfiguration() async {
    final configured = await WhatsAppBusinessService.isConfigured();
    final webhookConfigured =
        await WhatsAppBulkSenderService.isWebhookConfigured();
    setState(() {
      _isConfigured = configured;
      _isWebhookConfigured = webhookConfigured;
    });
  }

  Future<void> _sendTestMessage() async {
    // التحقق من الإعدادات
    if (!_isConfigured) {
      _showError('يرجى إعداد WhatsApp Business API أولاً من القائمة');
      return;
    }

    if (!_isWebhookConfigured) {
      _showError('يرجى إعداد رابط n8n Webhook أولاً');
      return;
    }

    if (_recipients.isEmpty) {
      _showError('يرجى إضافة مستلمين أولاً');
      return;
    }

    setState(() {
      _isSending = true;
      _lastResult = null;
    });

    try {
      // قراءة الإعدادات المحفوظة
      final phoneNumberId = await WhatsAppBusinessService.getPhoneNumberId();
      final accessToken = await WhatsAppBusinessService.getAccessToken();

      if (phoneNumberId == null || accessToken == null) {
        _showError('بيانات API غير مكتملة. يرجى إعداد الإعدادات أولاً');
        setState(() => _isSending = false);
        return;
      }

      final result = await WhatsAppBulkSenderService.sendTemplateMessages(
        templateType: _selectedTemplateType,
        recipients: _recipients,
        phoneNumberId: phoneNumberId,
        accessToken: accessToken,
        offerText: _offerTextController.text,
      );

      setState(() {
        _lastResult = result;
        _isSending = false;
      });

      if (result['success'] == true) {
        _showSuccess('تم الإرسال بنجاح!');
      } else {
        _showError('فشل الإرسال: ${result['message']}');
      }
    } catch (e) {
      setState(() {
        _isSending = false;
      });
      _showError('خطأ: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _showAddRecipientDialog() {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final expiryDateController = TextEditingController();
    final planNameController = TextEditingController();
    final priceController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إضافة مستلم جديد'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'الاسم *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneController,
                decoration: const InputDecoration(
                  labelText: 'رقم الهاتف *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone),
                  hintText: '07XXXXXXXXX',
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: expiryDateController,
                decoration: const InputDecoration(
                  labelText: 'تاريخ الانتهاء',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.calendar_today),
                  hintText: '25/12/2025',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: planNameController,
                decoration: const InputDecoration(
                  labelText: 'اسم الباقة',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.wifi),
                  hintText: 'FIBER 35',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: priceController,
                decoration: const InputDecoration(
                  labelText: 'السعر',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.attach_money),
                  hintText: '35000',
                ),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.trim().isEmpty ||
                  phoneController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('يرجى إدخال الاسم ورقم الهاتف'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              setState(() {
                _recipients.add({
                  'name': nameController.text.trim(),
                  'phoneNumber': phoneController.text.trim(),
                  'expiryDate': expiryDateController.text.trim(),
                  'planName': planNameController.text.trim(),
                  'price': priceController.text.trim(),
                });
              });

              Navigator.pop(context);
              _showSuccess('تمت إضافة المستلم بنجاح');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange[700],
              foregroundColor: Colors.white,
            ),
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
  }

  void _removeRecipient(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل تريد حذف "${_recipients[index]['name']}"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _recipients.removeAt(index);
              });
              Navigator.pop(context);
              _showSuccess('تم حذف المستلم');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
  }

  void _showWebhookSettingsDialog() async {
    final currentUrl = await WhatsAppBulkSenderService.getWebhookUrl();
    final urlController = TextEditingController(
      text: currentUrl ??
          'https://n8n.srv991906.hstgr.cloud/webhook/send-whatsapp-messages',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إعدادات n8n Webhook'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'رابط webhook من n8n:',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'تأكد من أن الـ workflow مفعّل في n8n',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: urlController,
              decoration: const InputDecoration(
                labelText: 'Webhook URL',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.link),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              final url = urlController.text.trim();
              if (url.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('يرجى إدخال رابط webhook'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              if (!url.startsWith('http://') && !url.startsWith('https://')) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                        'يرجى إدخال رابط صحيح يبدأ بـ http:// أو https://'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              await WhatsAppBulkSenderService.saveWebhookUrl(url);
              await _checkConfiguration();
              Navigator.pop(context);
              _showSuccess('تم حفظ رابط webhook بنجاح');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF25D366),
              foregroundColor: Colors.white,
            ),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إرسال رسائل WhatsApp جماعية'),
        backgroundColor: const Color(0xFF25D366),
        actions: [
          // زر إعدادات WhatsApp Business API
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'إعدادات WhatsApp API',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const WhatsAppBusinessConfigPage(),
                ),
              ).then((_) => _checkConfiguration()); // تحديث الحالة بعد العودة
            },
          ),
          // زر تقارير الإرسال
          IconButton(
            icon: const Icon(Icons.analytics_rounded),
            tooltip: 'تقارير الإرسال',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const WhatsAppBatchReportsPage(),
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // حالة الإعداد - WhatsApp API
            Card(
              color: _isConfigured ? Colors.green[50] : Colors.orange[50],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      _isConfigured ? Icons.check_circle : Icons.warning,
                      color: _isConfigured
                          ? Colors.green[700]
                          : Colors.orange[700],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isConfigured
                                ? 'WhatsApp API مُعد وجاهز'
                                : 'يرجى إعداد WhatsApp API أولاً',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: _isConfigured
                                  ? Colors.green[900]
                                  : Colors.orange[900],
                            ),
                          ),
                          if (!_isConfigured) ...[
                            const SizedBox(height: 4),
                            const Text(
                              'اذهب إلى: القائمة → WhatsApp Business API',
                              style: TextStyle(fontSize: 12),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // حالة الإعداد - n8n Webhook
            Card(
              color:
                  _isWebhookConfigured ? Colors.green[50] : Colors.orange[50],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      _isWebhookConfigured ? Icons.check_circle : Icons.warning,
                      color: _isWebhookConfigured
                          ? Colors.green[700]
                          : Colors.orange[700],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isWebhookConfigured
                                ? 'n8n Webhook مُعد وجاهز'
                                : 'يرجى إعداد رابط n8n Webhook',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: _isWebhookConfigured
                                  ? Colors.green[900]
                                  : Colors.orange[900],
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'رابط webhook من n8n لإرسال الرسائل',
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.settings),
                      onPressed: _showWebhookSettingsDialog,
                      tooltip: 'إعدادات Webhook',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // اختيار نوع القالب
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.description, color: Colors.blue[700]),
                        const SizedBox(width: 8),
                        const Text(
                          'نوع الرسالة',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...(_templateTypes.map((template) => RadioListTile<String>(
                          value: template['value'] as String,
                          groupValue: _selectedTemplateType,
                          onChanged: (value) {
                            setState(() {
                              _selectedTemplateType = value!;
                            });
                          },
                          title: Text(
                            template['label'] as String,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: (template['color'] as Color?)
                                  ?.withValues(alpha: 0.9),
                            ),
                          ),
                          subtitle: Text(
                            template['description'] as String,
                            style: const TextStyle(fontSize: 12),
                          ),
                          secondary: Icon(
                            template['icon'] as IconData,
                            color: template['color'] as Color?,
                          ),
                          activeColor: template['color'] as Color?,
                        ))),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // حقل العرض (يظهر فقط عند اختيار قالب المنتهي)
            if (_selectedTemplateType == 'sadara_expired') ...[
              Card(
                color: Colors.red[50],
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.local_offer, color: Colors.red[700]),
                          const SizedBox(width: 8),
                          const Text(
                            'نص العرض',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'سيظهر هذا النص في رسالة العرض للمشتركين المنتهية اشتراكاتهم',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _offerTextController,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: 'مثال: باقة FIBER 35 بسعر 30,000 د.ع فقط!',
                        ),
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // قائمة المستلمين
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.people, color: Colors.orange[700]),
                        const SizedBox(width: 8),
                        Text(
                          'المستلمون (${_recipients.length})',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        ElevatedButton.icon(
                          onPressed: _showAddRecipientDialog,
                          icon: const Icon(Icons.add, size: 20),
                          label: const Text('إضافة'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange[700],
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_recipients.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Text(
                            'لا يوجد مستلمين. اضغط "إضافة" لإضافة مستلم جديد',
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _recipients.length,
                        itemBuilder: (context, index) {
                          final recipient = _recipients[index];
                          return ListTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.person),
                            ),
                            title: Text(recipient['name'] ?? ''),
                            subtitle: Text(recipient['phoneNumber'] ?? ''),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _removeRecipient(index),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // زر الإرسال
            ElevatedButton.icon(
              onPressed: _isSending ? null : _sendTestMessage,
              icon: _isSending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send),
              label: Text(_isSending ? 'جاري الإرسال...' : 'إرسال الرسائل'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(16),
                textStyle: const TextStyle(fontSize: 16),
              ),
            ),
            const SizedBox(height: 16),

            // النتائج
            if (_lastResult != null) ...[
              Card(
                color: _lastResult!['success'] == true
                    ? Colors.green[50]
                    : Colors.red[50],
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _lastResult!['success'] == true
                                ? Icons.check_circle
                                : Icons.error,
                            color: _lastResult!['success'] == true
                                ? Colors.green[700]
                                : Colors.red[700],
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _lastResult!['success'] == true
                                ? 'نتائج الإرسال'
                                : 'فشل الإرسال',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_lastResult!['success'] == true) ...[
                        Text(
                          'عدد الرسائل المرسلة: ${_lastResult!['data']['totalSent']}',
                          style: const TextStyle(fontSize: 14),
                        ),
                        Text(
                          'عدد الفاشلة: ${_lastResult!['data']['totalFailed']}',
                          style: const TextStyle(fontSize: 14),
                        ),
                        Text(
                          'نسبة النجاح: ${_lastResult!['data']['successRate']}',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ] else ...[
                        Text(
                          'الخطأ: ${_lastResult!['message']}',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _offerTextController.dispose();
    super.dispose();
  }
}
