/// اسم الصفحة: الإعدادات
/// وصف الصفحة: صفحة إعدادات التطبيق والخيارات الشخصية
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsPage extends StatefulWidget {
  final String currentUserRole;
  final String currentUsername;

  const SettingsPage({
    super.key,
    required this.currentUserRole,
    required this.currentUsername,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final TextEditingController _rasoulPhoneController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadRasoulPhone();
  }

  @override
  void dispose() {
    _rasoulPhoneController.dispose();
    super.dispose();
  }

  Future<void> _loadRasoulPhone() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedPhone = prefs.getString('rasoul_phone_number') ?? '';
      _rasoulPhoneController.text = savedPhone;
    } catch (e) {
      print('Error loading Rasoul phone');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveRasoulPhone() async {
    final phone = _rasoulPhoneController.text.trim();

    if (phone.isEmpty) {
      _showMessage('يرجى إدخال رقم هاتف رسول', isError: true);
      return;
    }

    // التحقق من صحة رقم الهاتف (أرقام عراقية)
    final phoneRegex = RegExp(r'^(07[3-9]\d{8}|964\d{10})$');
    if (!phoneRegex.hasMatch(phone)) {
      _showMessage('يرجى إدخال رقم هاتف صحيح (07xxxxxxxx أو 964xxxxxxxxxx)',
          isError: true);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('rasoul_phone_number', phone);

      _showMessage('تم حفظ رقم هاتف رسول بنجاح ✅');
    } catch (e) {
      print('Error saving Rasoul phone');
      _showMessage('خطأ في حفظ رقم الهاتف', isError: true);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: Duration(seconds: isError ? 4 : 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الإعدادات'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // معلومات المستخدم
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'معلومات المستخدم',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Icon(Icons.person, color: Colors.blue),
                              const SizedBox(width: 8),
                              Text(
                                'المستخدم: ${widget.currentUsername}',
                                style: const TextStyle(fontSize: 16),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.admin_panel_settings,
                                  color: Colors.orange),
                              const SizedBox(width: 8),
                              Text(
                                'الدور: ${widget.currentUserRole}',
                                style: const TextStyle(fontSize: 16),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // إعدادات الإشعارات
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.notifications, color: Colors.green),
                              SizedBox(width: 8),
                              Text(
                                'إعدادات الإشعارات',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'رقم هاتف القائد رسول للإشعارات:',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _rasoulPhoneController,
                            decoration: InputDecoration(
                              labelText: 'رقم هاتف رسول *',
                              hintText: '07xxxxxxxx أو 964xxxxxxxxxx',
                              border: const OutlineInputBorder(),
                              prefixIcon:
                                  const Icon(Icons.phone, color: Colors.green),
                              suffixIcon: IconButton(
                                icon:
                                    const Icon(Icons.save, color: Colors.blue),
                                onPressed: _saveRasoulPhone,
                                tooltip: 'حفظ الرقم',
                              ),
                            ),
                            keyboardType: TextInputType.phone,
                            maxLength: 15,
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.info_outline,
                                  size: 16, color: Colors.grey),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  'سيتم إرسال إشعارات المهام الجديدة لهذا الرقم',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _saveRasoulPhone,
                              icon: const Icon(Icons.save),
                              label: const Text('حفظ الإعدادات'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // معلومات إضافية
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.info, color: Colors.orange),
                              SizedBox(width: 8),
                              Text(
                                'معلومات مهمة',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _buildInfoRow('إشعارات المهام:',
                              'سيتم إرسال إشعار واتساب للقائد رسول عند إضافة أي مهمة جديدة'),
                          _buildInfoRow('صلاحية التعديل:',
                              'فقط المدير والقائد يمكنهم تعديل هذه الإعدادات'),
                          _buildInfoRow('رقم الهاتف:',
                              'يجب أن يكون رقم هاتف عراقي صحيح مُسجل في واتساب'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildInfoRow(String title, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '• ',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[700],
              fontWeight: FontWeight.bold,
            ),
          ),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[700],
                ),
                children: [
                  TextSpan(
                    text: title,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  TextSpan(text: ' $description'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
