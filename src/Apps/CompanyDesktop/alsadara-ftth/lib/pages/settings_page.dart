/// اسم الصفحة: الإعدادات
/// وصف الصفحة: صفحة إعدادات التطبيق والخيارات الشخصية
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../frontend/frontend.dart';

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
        backgroundColor: isError ? SdColors.danger : SdColors.success,
        duration: Duration(seconds: isError ? 4 : 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SdPage(
      maxWidth: SdSpace.formMax,
      scrollable: !_isLoading,
      appBar: const SdAppBar(title: 'الإعدادات'),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // معلومات المستخدم
                SdCard(
                  title: 'معلومات المستخدم',
                  icon: Icons.person,
                  tone: SdGroup.admin.tone,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SdInfoRow(
                        label: 'المستخدم',
                        value: widget.currentUsername,
                        icon: Icons.person,
                      ),
                      SdInfoRow(
                        label: 'الدور',
                        value: widget.currentUserRole,
                        icon: Icons.admin_panel_settings,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: SdSpace.lg),
                // إعدادات الإشعارات
                SdCard(
                  title: 'إعدادات الإشعارات',
                  icon: Icons.notifications,
                  tone: SdStatus.success.tone,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'رقم هاتف القائد رسول للإشعارات:',
                        style: SdText.label,
                      ),
                      const SizedBox(height: SdSpace.xs),
                      TextFormField(
                        controller: _rasoulPhoneController,
                        decoration: InputDecoration(
                          labelText: 'رقم هاتف رسول *',
                          hintText: '07xxxxxxxx أو 964xxxxxxxxxx',
                          border: const OutlineInputBorder(),
                          prefixIcon:
                              const Icon(Icons.phone, color: SdColors.success),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.save, color: SdColors.primary),
                            onPressed: _saveRasoulPhone,
                            tooltip: 'حفظ الرقم',
                          ),
                        ),
                        keyboardType: TextInputType.phone,
                        maxLength: 15,
                      ),
                      const SizedBox(height: SdSpace.xs),
                      Row(
                        children: const [
                          Icon(Icons.info_outline, size: 16, color: SdColors.faint),
                          SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'سيتم إرسال إشعارات المهام الجديدة لهذا الرقم',
                              style: SdText.caption,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: SdSpace.sm),
                      SdButton(
                        label: 'حفظ الإعدادات',
                        icon: Icons.save,
                        expand: true,
                        onPressed: _saveRasoulPhone,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: SdSpace.lg),
                // معلومات إضافية
                SdCard(
                  title: 'معلومات مهمة',
                  icon: Icons.info,
                  tone: SdStatus.warning.tone,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInfoRow('إشعارات المهام:',
                          'سيتم إرسال إشعار واتساب للقائد رسول عند إضافة أي مهمة جديدة'),
                      _buildInfoRow('صلاحية التعديل:',
                          'فقط المدير والقائد يمكنهم تعديل هذه الإعدادات'),
                      _buildInfoRow('رقم الهاتف:',
                          'يجب أن يكون رقم هاتف عراقي صحيح مُسجل في واتساب'),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildInfoRow(String title, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: SdText.label),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: SdText.body,
                children: [
                  TextSpan(
                    text: title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
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
