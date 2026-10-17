import 'dart:convert';
import 'package:flutter/material.dart';
import '../frontend/frontend.dart'; // نظام تصميم الصدارة الموحّد (sd)
import '../services/whatsapp_business_service.dart';

/// صفحة إعدادات WhatsApp Business API
class WhatsAppBusinessConfigPage extends StatefulWidget {
  const WhatsAppBusinessConfigPage({super.key});

  @override
  State<WhatsAppBusinessConfigPage> createState() =>
      _WhatsAppBusinessConfigPageState();
}

class _WhatsAppBusinessConfigPageState
    extends State<WhatsAppBusinessConfigPage> {
  final _formKey = GlobalKey<FormState>();

  final _userTokenController = TextEditingController();
  final _appTokenController = TextEditingController();
  final _phoneNumberIdController = TextEditingController();
  final _businessAccountIdController = TextEditingController();
  final _testPhoneController = TextEditingController();

  bool _isLoading = false;
  bool _isSaving = false;
  bool _isConfigured = false;
  bool _showTokens = false;

  @override
  void initState() {
    super.initState();
    _loadExistingConfig();
  }

  @override
  void dispose() {
    _userTokenController.dispose();
    _appTokenController.dispose();
    _phoneNumberIdController.dispose();
    _businessAccountIdController.dispose();
    _testPhoneController.dispose();
    super.dispose();
  }

  Future<void> _loadExistingConfig() async {
    setState(() => _isLoading = true);

    try {
      // تحميل من config.json إن وجد
      await _loadFromConfigFile();

      // ثم تحميل الإعدادات المحفوظة (تأخذ الأولوية)
      final config = await WhatsAppBusinessService.getConfigInfo();

      if (config['user_token']?.isNotEmpty ?? false) {
        _userTokenController.text = config['user_token'] ?? '';
      }
      if (config['app_token']?.isNotEmpty ?? false) {
        _appTokenController.text = config['app_token'] ?? '';
      }
      if (config['phone_number_id']?.isNotEmpty ?? false) {
        _phoneNumberIdController.text = config['phone_number_id'] ?? '';
      }
      if (config['business_account_id']?.isNotEmpty ?? false) {
        _businessAccountIdController.text = config['business_account_id'] ?? '';
      }

      _isConfigured = await WhatsAppBusinessService.isConfigured();
    } catch (e) {
      debugPrint('خطأ في تحميل الإعدادات');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadFromConfigFile() async {
    try {
      final configString =
          await DefaultAssetBundle.of(context).loadString('assets/config.json');
      final configData = jsonDecode(configString);

      // تحميل القيم من config.json كقيم افتراضية (تظهر دائماً)
      final appToken = configData['whatsapp']?['app_token'] ?? '';
      final phoneNumberId = configData['whatsapp']?['phone_number_id'] ?? '';
      final wabaId = configData['whatsapp']?['waba_id'] ?? '';

      _appTokenController.text = appToken;
      _phoneNumberIdController.text = phoneNumberId;
      _businessAccountIdController.text = wabaId;

      // حفظ القيم في SharedPreferences تلقائياً لتكون متاحة لـ isConfigured()
      // فقط القيم الموجودة في config.json (بدون مسح user_token المحفوظ سابقاً)
      if (phoneNumberId.isNotEmpty) {
        await WhatsAppBusinessService.savePhoneNumberId(phoneNumberId);
      }
      if (appToken.isNotEmpty) {
        await WhatsAppBusinessService.saveAppToken(appToken);
      }
      if (wabaId.isNotEmpty) {
        await WhatsAppBusinessService.saveBusinessAccountId(wabaId);
      }

      debugPrint('✅ تم تحميل الإعدادات من config.json');
      debugPrint('   Phone Number ID: $phoneNumberId');
      debugPrint('   WABA ID: $wabaId');
    } catch (e) {
      debugPrint('⚠️ لم يتم العثور على config.json');
    }
  }

  Future<void> _saveConfig() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      // حفظ البيانات أولاً
      await WhatsAppBusinessService.saveCredentials(
        userToken: _userTokenController.text.trim(),
        appToken: _appTokenController.text.trim().isEmpty
            ? null
            : _appTokenController.text.trim(),
        phoneNumberId: _phoneNumberIdController.text.trim(),
        businessAccountId: _businessAccountIdController.text.trim().isEmpty
            ? null
            : _businessAccountIdController.text.trim(),
      );

      _isConfigured = true;

      // تم حفظ البيانات بنجاح - بدون إشعار
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ خطأ في حفظ الإعدادات'),
            backgroundColor: SdColors.danger,
          ),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _verifyToken() async {
    // التحقق من أن الحقول ليست فارغة
    if (_userTokenController.text.trim().isEmpty ||
        _phoneNumberIdController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ يرجى إدخال User Token و Phone Number ID أولاً'),
          backgroundColor: SdColors.warning,
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final isValid = await WhatsAppBusinessService.verifyToken();

    if (mounted) {
      if (isValid) {
        final isPermanent = _userTokenController.text.length > 150;
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: SdColors.success, size: 32),
                SizedBox(width: 10),
                Text('Token صالح ✅'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '🎉 تم التحقق بنجاح!',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isPermanent
                        ? SdColors.successTint
                        : SdColors.warningTint,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isPermanent ? SdColors.success : SdColors.warning,
                      width: 2,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isPermanent ? Icons.verified : Icons.access_time,
                            color: isPermanent ? SdColors.success : SdColors.warning,
                            size: 24,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              isPermanent ? '🔐 توكن دائم' : '⏰ توكن مؤقت',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color:
                                    isPermanent ? SdColors.success : SdColors.warning,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isPermanent
                            ? 'لن ينتهي - استخدمه بثقة! 🎯'
                            : 'سينتهي بعد 24 ساعة - احصل على توكن دائم من System User',
                        style: TextStyle(
                          fontSize: 13,
                          color: isPermanent
                              ? SdColors.successEdge
                              : SdColors.warningEdge,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '✅ جاهز للاستخدام الآن!',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: SdColors.success,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('رائع!'),
              ),
            ],
          ),
        );
      } else {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.error_outline, color: SdColors.danger, size: 28),
                SizedBox(width: 10),
                Text('Token غير صالح'),
              ],
            ),
            content: const SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'تحقق من التالي:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 10),
                  Text('1️⃣ User Token صحيح ولم ينته صلاحيته'),
                  SizedBox(height: 5),
                  Text('2️⃣ Phone Number ID صحيح (15 رقماً تقريباً)'),
                  SizedBox(height: 5),
                  Text('3️⃣ رقم الهاتف مفعّل في WhatsApp Business API'),
                  SizedBox(height: 5),
                  Text('4️⃣ الاتصال بالإنترنت متوفر'),
                  SizedBox(height: 15),
                  Text(
                    'للحصول على التوكنات الصحيحة:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: SdColors.info,
                    ),
                  ),
                  SizedBox(height: 5),
                  Text('• ادخل على developers.facebook.com'),
                  Text('• اختر تطبيقك → WhatsApp → API Setup'),
                  Text('• انسخ User Token و Phone Number ID'),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('حسناً'),
              ),
            ],
          ),
        );
      }
    }

    setState(() => _isLoading = false);
  }

  Future<void> _sendTestMessage() async {
    if (_testPhoneController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ يرجى إدخال رقم هاتف للاختبار'),
          backgroundColor: SdColors.warning,
        ),
      );
      return;
    }

    // عرض دايلوج لاختيار نوع الرسالة
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('اختر نوع الرسالة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'رسائل القوالب (Templates) يمكن إرسالها في أي وقت.\nالرسائل النصية العادية تتطلب رد المستلم خلال 24 ساعة.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.description, color: SdColors.success),
              title: const Text('رسالة قالب (موصى به)'),
              subtitle: const Text('يمكن إرسالها دائماً'),
              onTap: () => Navigator.pop(context, 'template'),
            ),
            ListTile(
              leading: const Icon(Icons.message, color: SdColors.warning),
              title: const Text('رسالة نصية عادية'),
              subtitle: const Text('خلال 24 ساعة من رد المستلم'),
              onTap: () => Navigator.pop(context, 'text'),
            ),
          ],
        ),
      ),
    );

    if (choice == null) return;

    if (choice == 'template') {
      await _sendTemplateMessage();
    } else {
      await _sendTextMessage();
    }
  }

  Future<void> _sendTextMessage() async {
    setState(() => _isLoading = true);

    final result = await WhatsAppBusinessService.sendTextMessage(
      to: _testPhoneController.text.trim(),
      message: 'مرحباً! هذه رسالة تجريبية من تطبيق الصدارة.',
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result != null
                ? '✅ تم إرسال الرسالة التجريبية بنجاح'
                : '❌ فشل في إرسال الرسالة - راجع Console للتفاصيل',
          ),
          backgroundColor: result != null ? SdColors.success : SdColors.danger,
        ),
      );
    }

    setState(() => _isLoading = false);
  }

  Future<void> _sendTemplateMessage() async {
    // اختيار القالب
    final template = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('اختر قالب الرسالة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.check_circle, color: SdColors.success),
              title: const Text('6'),
              subtitle:
                  const Text('Your RSVP for {{1}} by {{2}} is confirmed!'),
              trailing: const Chip(
                label: Text('متغيرات'),
                backgroundColor: SdColors.success,
              ),
              onTap: () => Navigator.pop(context, '6'),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.warning, color: SdColors.warning),
              title: const Text('hello_world'),
              subtitle: const Text('للاختبار فقط - لا يعمل على أرقام الإنتاج'),
              enabled: false,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );

    if (template == null) return;

    List<String>? parameters;

    // إذا كان القالب "6" يحتاج متغيرات
    if (template == '6') {
      final param1Controller = TextEditingController();
      final param2Controller = TextEditingController();

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('إدخال قيم المتغيرات'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('القالب: Your RSVP for {{1}} by {{2}} is confirmed!'),
              const SizedBox(height: 16),
              TextField(
                controller: param1Controller,
                decoration: const InputDecoration(
                  labelText: 'المتغير 1 ({{1}})',
                  hintText: 'مثال: Meeting',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: param2Controller,
                decoration: const InputDecoration(
                  labelText: 'المتغير 2 ({{2}})',
                  hintText: 'مثال: John',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('إرسال'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      parameters = [
        param1Controller.text.trim(),
        param2Controller.text.trim(),
      ];
    }

    setState(() => _isLoading = true);

    final result = await WhatsAppBusinessService.sendTemplateMessage(
      to: _testPhoneController.text.trim(),
      templateName: template,
      languageCode: 'en_US',
      parameters: parameters,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result != null
                ? '✅ تم إرسال رسالة القالب بنجاح'
                : '❌ فشل في إرسال الرسالة - راجع Console للتفاصيل',
          ),
          backgroundColor: result != null ? SdColors.success : SdColors.danger,
          duration: const Duration(seconds: 4),
        ),
      );
    }

    setState(() => _isLoading = false);
  }

  Future<void> _clearConfig() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: const Text('هل أنت متأكد من حذف جميع بيانات الاعتماد؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: SdColors.danger),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await WhatsAppBusinessService.clearCredentials();
      _userTokenController.clear();
      _appTokenController.clear();
      _phoneNumberIdController.clear();
      _businessAccountIdController.clear();
      setState(() => _isConfigured = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ تم حذف جميع البيانات'),
            backgroundColor: SdColors.success,
          ),
        );
      }
    }
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.help_outline, color: SdColors.info, size: 28),
            SizedBox(width: 10),
            Expanded(child: Text('كيف تحصل على التوكنات؟')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // توكن دائم (موصى به)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: SdColors.successTint,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: SdColors.success, width: 2),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.verified, color: SdColors.success, size: 24),
                        SizedBox(width: 8),
                        Text(
                          '✅ توكن دائم (موصى به)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: SdColors.success,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 10),
                    Text(
                      '1. افتح business.facebook.com',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 5),
                    Text('2. Settings → System Users'),
                    SizedBox(height: 5),
                    Text('3. Add (أنشئ مستخدم نظام)'),
                    SizedBox(height: 5),
                    Text('4. اختر دور: Admin'),
                    SizedBox(height: 5),
                    Text('5. Generate New Token'),
                    SizedBox(height: 5),
                    Text('6. اختر تطبيقك'),
                    SizedBox(height: 5),
                    Text('7. اختر الصلاحيات:'),
                    Text('   • whatsapp_business_messaging'),
                    Text('   • whatsapp_business_management'),
                    SizedBox(height: 5),
                    Text('8. احفظ التوكن فوراً! 🔐'),
                    SizedBox(height: 10),
                    Text(
                      '💡 هذا التوكن لا ينتهي أبداً!',
                      style: TextStyle(
                        color: SdColors.success,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              // توكن مؤقت (للتجربة)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: SdColors.warningTint,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: SdColors.warning),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.access_time, color: SdColors.warning, size: 24),
                        SizedBox(width: 8),
                        Text(
                          '⏰ توكن مؤقت (للتجربة)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: SdColors.warning,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 10),
                    Text('1. افتح developers.facebook.com'),
                    SizedBox(height: 5),
                    Text('2. اختر تطبيقك'),
                    SizedBox(height: 5),
                    Text('3. WhatsApp → API Setup'),
                    SizedBox(height: 5),
                    Text('4. انسخ Temporary access token'),
                    SizedBox(height: 10),
                    Text(
                      '⚠️ ينتهي بعد 24 ساعة!',
                      style: TextStyle(
                        color: SdColors.danger,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              // Phone Number ID
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: SdColors.infoTint,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: SdColors.info),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.phone, color: SdColors.info, size: 24),
                        SizedBox(width: 8),
                        Text(
                          '📱 Phone Number ID',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: SdColors.info,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 10),
                    Text('من نفس صفحة API Setup'),
                    SizedBox(height: 5),
                    Text('رقم طويل (~15 رقم)'),
                    SizedBox(height: 5),
                    Text('مثال: 123456789012345'),
                    SizedBox(height: 5),
                    Text(
                      '⚠️ ليس رقم هاتفك العادي!',
                      style: TextStyle(
                        color: SdColors.danger,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('فهمت'),
          ),
        ],
      ),
    );
  }

  // بناء عنوان القسم
  Widget _buildSectionTitle(String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [SdColors.accentTint, SdColors.accentTint],
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: SdColors.accentLight),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: SdColors.accentEdge,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: SdColors.accentEdge,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // بناء حقل مع إشارة config.json
  Widget _buildConfigField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required bool fromConfig,
    bool obscureText = false,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        prefixIcon: Icon(icon, color: SdColors.success),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (fromConfig && controller.text.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(
                  color: SdColors.successTint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle,
                        size: 14, color: SdColors.successEdge),
                    const SizedBox(width: 4),
                    Text(
                      'config',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: SdColors.successEdge,
                      ),
                    ),
                  ],
                ),
              ),
            if (obscureText)
              IconButton(
                icon:
                    Icon(_showTokens ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _showTokens = !_showTokens),
              ),
          ],
        ),
        filled: true,
        fillColor: fromConfig && controller.text.isNotEmpty
            ? SdColors.successTint
            : null,
      ),
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SdTheme.scope(
      child: Scaffold(
      backgroundColor: SdColors.ground,
      appBar: SdAppBar(
        title: 'إعدادات WhatsApp Business API',
        actions: [
          SdAppBarAction(
            icon: Icons.help_outline,
            label: 'كيف تحصل على التوكنات؟',
            onPressed: _showHelpDialog,
          ),
          if (_isConfigured)
            SdAppBarAction(
              icon: Icons.delete_outline,
              label: 'حذف الإعدادات',
              onPressed: _clearConfig,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              top: false,
              child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // حالة الإعداد
                    Card(
                      color: _isConfigured
                          ? SdColors.successTint
                          : SdColors.warningTint,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            Icon(
                              _isConfigured
                                  ? Icons.check_circle
                                  : Icons.warning,
                              color:
                                  _isConfigured ? SdColors.success : SdColors.warning,
                              size: 32,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _isConfigured
                                    ? 'WhatsApp Business API مُعد وجاهز'
                                    : 'يرجى إدخال بيانات الاعتماد',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: _isConfigured
                                      ? SdColors.successEdge
                                      : SdColors.warningEdge,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // قسم 1: البيانات الأساسية (من config.json)
                    _buildSectionTitle(
                        '📋 البيانات الأساسية', 'محملة من config.json'),
                    const SizedBox(height: 12),

                    // Phone Number ID (من config.json - قابل للتعديل)
                    _buildConfigField(
                      controller: _phoneNumberIdController,
                      label: '* Phone Number ID',
                      hint: '879614651900630',
                      icon: Icons.phone_android,
                      fromConfig: true,
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'يرجى إدخال Phone Number ID';
                        }
                        if (value.trim().contains('+') ||
                            value.trim().contains('-')) {
                          return '❌ Phone Number ID لا يحتوي على + أو -';
                        }
                        if (value.trim().length < 10) {
                          return 'Phone Number ID قصير جداً (~15 رقم)';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),

                    // App Token (من config.json - قابل للتعديل)
                    _buildConfigField(
                      controller: _appTokenController,
                      label: 'App Token',
                      hint: '1379921973529118|D4uUL...',
                      icon: Icons.app_settings_alt,
                      fromConfig: true,
                      obscureText: !_showTokens,
                    ),
                    const SizedBox(height: 12),

                    // Business Account ID (من config.json - قابل للتعديل)
                    _buildConfigField(
                      controller: _businessAccountIdController,
                      label: 'Business Account ID (WABA)',
                      hint: '1199949112036660',
                      icon: Icons.business_center,
                      fromConfig: true,
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 24),

                    // قسم 2: User Token (يحتاج إدخال يدوي)
                    _buildSectionTitle(
                        '🔐 User Access Token', 'مطلوب - أدخله يدوياً'),
                    const SizedBox(height: 12),

                    TextFormField(
                      controller: _userTokenController,
                      decoration: InputDecoration(
                        labelText: '* User Access Token (دائم)',
                        hintText: 'EAATnCB8Myh4BQ... (الصق التوكن الدائم)',
                        border: const OutlineInputBorder(),
                        prefixIcon:
                            const Icon(Icons.vpn_key, color: SdColors.danger),
                        suffixIcon: IconButton(
                          icon: Icon(_showTokens
                              ? Icons.visibility_off
                              : Icons.visibility),
                          onPressed: () =>
                              setState(() => _showTokens = !_showTokens),
                        ),
                        filled: true,
                        fillColor: SdColors.dangerTint,
                      ),
                      obscureText: !_showTokens,
                      maxLines: _showTokens ? 3 : 1,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'يرجى إدخال User Token';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: SdColors.infoTint,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: SdColors.infoTint),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info,
                              color: SdColors.infoEdge, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '💡 احصل على التوكن الدائم من:\nBusiness Settings > System Users > Generate Token',
                              style: TextStyle(
                                  fontSize: 12, color: SdColors.infoEdge),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // قسم 3: الاختبار
                    _buildSectionTitle('🧪 اختبار الاتصال', 'اختبار الإعداد'),
                    const SizedBox(height: 12),

                    TextFormField(
                      controller: _testPhoneController,
                      decoration: const InputDecoration(
                        labelText: 'رقم اختبار (مع رمز الدولة)',
                        hintText: '+9647XXXXXXXXX',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.phone, color: SdColors.warning),
                        helperText: 'يجب أن يكون الرقم مسجلاً في WhatsApp',
                      ),
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 24),

                    // أزرار الحفظ والتحقق
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isSaving ? null : _saveConfig,
                            icon: _isSaving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.save),
                            label: const Text('حفظ الإعدادات'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: SdColors.success,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.all(16),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isConfigured ? _verifyToken : null,
                            icon: const Icon(Icons.verified_user),
                            label: const Text('التحقق من Token'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.all(16),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // زر اختبار الإرسال
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isConfigured ? _sendTestMessage : null,
                        icon: const Icon(Icons.send, size: 24),
                        label: const Text('إرسال رسالة اختبار',
                            style: TextStyle(fontSize: 16)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: SdColors.info,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.all(20),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // زر الحذف
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _clearConfig,
                        icon:
                            const Icon(Icons.delete_outline, color: SdColors.danger),
                        label: const Text('حذف جميع البيانات',
                            style: TextStyle(color: SdColors.danger)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.all(16),
                          side: const BorderSide(color: SdColors.danger),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // ملاحظة config.json
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: SdColors.warningTint,
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: SdColors.warning, width: 2),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.lightbulb,
                              color: SdColors.warningText, size: 28),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '💡 البيانات المحملة من config.json تظهر تلقائياً في الحقول. يمكنك تعديلها والحفظ.',
                              style: TextStyle(
                                fontSize: 13,
                                color: SdColors.warningEdge,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        color: SdColors.infoTint,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: SdColors.infoTint),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.info_outline,
                                    color: SdColors.infoEdge),
                                const SizedBox(width: 8),
                                Text(
                                  'إرشادات الحصول على البيانات',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: SdColors.infoEdge,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _buildInstructionStep(
                              '1. افتح',
                              'developers.facebook.com',
                            ),
                            _buildInstructionStep(
                              '2. اذهب إلى',
                              'My Apps > WhatsApp > API Setup',
                            ),
                            _buildInstructionStep(
                              '3. انسخ',
                              'User Access Token و Phone Number ID',
                            ),
                            _buildInstructionStep(
                              '4. احفظها هنا',
                              'واضغط "حفظ الإعدادات"',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ),
      ),
    );
  }

  Widget _buildInstructionStep(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: SdColors.infoEdge),
            ),
          ),
        ],
      ),
    );
  }
}
