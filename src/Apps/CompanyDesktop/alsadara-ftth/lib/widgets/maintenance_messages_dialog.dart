import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/maintenance_messages.dart';
import '../services/maintenance_messages_service.dart';

class MaintenanceMessagesDialog extends StatefulWidget {
  final String currentUserName;

  const MaintenanceMessagesDialog({
    super.key,
    required this.currentUserName,
  });

  @override
  State<MaintenanceMessagesDialog> createState() => _MaintenanceMessagesDialogState();
}

class _MaintenanceMessagesDialogState extends State<MaintenanceMessagesDialog> {
  final _passwordController = TextEditingController();
  final _openTaskController = TextEditingController();
  final _inProgressController = TextEditingController();
  final _completedController = TextEditingController();
  final _cancelledController = TextEditingController();
  final _defaultController = TextEditingController();
  final _supportPhoneController = TextEditingController();
  final _companyNameController = TextEditingController();
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isPasswordVerified = false;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _showPasswordChangeSection = false;
  MaintenanceMessages? _currentMessages;

  @override
  void initState() {
    super.initState();
    _loadCurrentMessages();
  }

  Future<void> _loadCurrentMessages() async {
    final messages = await MaintenanceMessagesService.getMessages();
    setState(() {
      _currentMessages = messages;
      _populateControllers(messages);
    });
  }

  void _populateControllers(MaintenanceMessages messages) {
    _openTaskController.text = messages.openTaskMessage;
    _inProgressController.text = messages.inProgressMessage;
    _completedController.text = messages.completedMessage;
    _cancelledController.text = messages.cancelledMessage;
    _defaultController.text = messages.defaultMessage;
    _supportPhoneController.text = messages.supportPhone;
    _companyNameController.text = messages.companyName;
  }

  Future<void> _verifyPassword() async {
    if (_passwordController.text.isEmpty) {
      _showSnackBar('يرجى إدخال كلمة المرور', Colors.orange);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final isValid = await MaintenanceMessagesService.verifyPassword(_passwordController.text);

    setState(() {
      _isLoading = false;
      _isPasswordVerified = isValid;
    });

    if (isValid) {
      _showSnackBar('تم التحقق من كلمة المرور بنجاح', Colors.green);
    } else {
      _showSnackBar('كلمة المرور غير صحيحة', Colors.red);
    }
  }

  Future<void> _saveMessages() async {
    if (!_isPasswordVerified) {
      _showSnackBar('يجب التحقق من كلمة المرور أولاً', Colors.orange);
      return;
    }

    // التحقق من وجود المحتوى المطلوب
    if (_openTaskController.text.isEmpty ||
        _inProgressController.text.isEmpty ||
        _completedController.text.isEmpty ||
        _cancelledController.text.isEmpty ||
        _supportPhoneController.text.isEmpty ||
        _companyNameController.text.isEmpty) {
      _showSnackBar('يرجى ملء جميع الحقول المطلوبة', Colors.orange);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final updatedMessages = MaintenanceMessages(
      openTaskMessage: _openTaskController.text,
      inProgressMessage: _inProgressController.text,
      completedMessage: _completedController.text,
      cancelledMessage: _cancelledController.text,
      defaultMessage: _defaultController.text,
      supportPhone: _supportPhoneController.text,
      companyName: _companyNameController.text,
      lastUpdated: DateTime.now(),
      updatedBy: widget.currentUserName,
    );

    final success = await MaintenanceMessagesService.saveMessages(updatedMessages);

    setState(() {
      _isLoading = false;
    });

    if (success) {
      _showSnackBar('تم حفظ الرسائل بنجاح', Colors.green);
      Navigator.of(context).pop(true); // إرجاع true للإشارة إلى نجاح الحفظ
    } else {
      _showSnackBar('فشل في حفظ الرسائل', Colors.red);
    }
  }

  Future<void> _resetToDefault() async {
    final confirmed = await _showConfirmationDialog(
      'إعادة تعيين إلى الافتراضي',
      'هل أنت متأكد من إعادة تعيين جميع الرسائل إلى القيم الافتراضية؟',
    );

    if (confirmed) {
      setState(() {
        _isLoading = true;
      });

      final success = await MaintenanceMessagesService.resetToDefault();

      if (success) {
        await _loadCurrentMessages();
        _showSnackBar('تم إعادة التعيين بنجاح', Colors.green);
      } else {
        _showSnackBar('فشل في إعادة التعيين', Colors.red);
      }

      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<bool> _showConfirmationDialog(String title, String content) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('تأكيد', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    ) ?? false;
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.9,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // العنوان
            Row(
              children: [
                Icon(Icons.message, color: Colors.blue, size: 28),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'إعدادات رسائل الصيانة',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const Divider(),

            // محتوى الحوار
            Expanded(
              child: _isPasswordVerified
                ? _buildMessagesEditor()
                : _buildPasswordScreen(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPasswordScreen() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock, size: 80, color: Colors.blue.shade300),
            const SizedBox(height: 24),
            const Text(
              'يرجى إدخال كلمة المرور للوصول إلى إعدادات الرسائل',
              style: TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'كلمة المرور',
                prefixIcon: const Icon(Icons.lock),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                ),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _verifyPassword(),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _verifyPassword,
                child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('التحقق'),
              ),
            ),
            const SizedBox(height: 16),

          ],
        ),
      ),
    );
  }

  Widget _buildMessagesEditor() {
    return Column(
      children: [
        // معلومات آخر تحديث
        if (_currentMessages != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.info, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'آخر تحديث: ${DateFormat('yyyy-MM-dd HH:mm').format(_currentMessages!.lastUpdated)} بواسطة ${_currentMessages!.updatedBy}',
                    style: TextStyle(color: Colors.blue.shade700, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // المحرر
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                _buildMessageField('معلومات الشركة ورقم الدعم', 'اسم الشركة', _companyNameController, false),
                _buildMessageField('', 'رقم هاتف الدعم', _supportPhoneController, false),
                const SizedBox(height: 16),
                _buildMessageField('رسالة المهام المفتوحة', 'الرسالة التي تُرسل للمشتركين عند فتح مهمة جديدة', _openTaskController, true),
                _buildMessageField('رسالة المهام قيد التنفيذ', 'الرسالة التي تُرسل عندما تكون المهمة قيد التنفيذ', _inProgressController, true),
                _buildMessageField('رسالة المهام المكتملة', 'الرسالة التي تُرسل عند إكمال المهمة', _completedController, true),
                _buildMessageField('رسالة المهام الملغية', 'الرسالة التي تُرسل عند إلغاء المهمة', _cancelledController, true),
                _buildMessageField('الرسالة الافتراضية', 'رسالة عامة للحالات الأخرى', _defaultController, true),
              ],
            ),
          ),
        ),

        // قسم تغيير كلمة المرور
        if (_showPasswordChangeSection) ...[
          const SizedBox(height: 16),
          Text(
            'تغيير كلمة المرور',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue.shade800),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _oldPasswordController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'كلمة المرور القديمة',
              prefixIcon: Icon(Icons.lock),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _newPasswordController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'كلمة المرور الجديدة',
              prefixIcon: Icon(Icons.lock),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirmPasswordController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'تأكيد كلمة المرور الجديدة',
              prefixIcon: Icon(Icons.lock),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _changePassword,
              child: _isLoading
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text('تغيير كلمة المرور'),
            ),
          ),
        ],

        // الأزرار
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isLoading ? null : () {
                  setState(() {
                    _showPasswordChangeSection = !_showPasswordChangeSection;
                  });
                },
                icon: const Icon(Icons.password),
                label: const Text('تغيير كلمة المرور'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isLoading ? null : _resetToDefault,
                icon: const Icon(Icons.restore),
                label: const Text('إعادة تعيين'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _saveMessages,
                icon: _isLoading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save),
                label: const Text('حفظ التغييرات'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMessageField(String title, String hint, TextEditingController controller, bool isMultiline) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty) ...[
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
          ],
          TextField(
            controller: controller,
            maxLines: isMultiline ? 6 : 1,
            decoration: InputDecoration(
              hintText: hint,
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _changePassword() async {
    if (_oldPasswordController.text.isEmpty || _newPasswordController.text.isEmpty || _confirmPasswordController.text.isEmpty) {
      _showSnackBar('يرجى ملء جميع حقول كلمة المرور', Colors.orange);
      return;
    }

    if (_newPasswordController.text != _confirmPasswordController.text) {
      _showSnackBar('كلمة المرور الجديدة وتأكيد كلمة المرور غير متطابقتين', Colors.orange);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final success = await MaintenanceMessagesService.changePassword(
      _oldPasswordController.text,
      _newPasswordController.text,
    );

    setState(() {
      _isLoading = false;
    });

    if (success) {
      _showSnackBar('تم تغيير كلمة المرور بنجاح', Colors.green);
      setState(() {
        _showPasswordChangeSection = false;
        _oldPasswordController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();
      });
    } else {
      _showSnackBar('فشل في تغيير كلمة المرور', Colors.red);
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _openTaskController.dispose();
    _inProgressController.dispose();
    _completedController.dispose();
    _cancelledController.dispose();
    _defaultController.dispose();
    _supportPhoneController.dispose();
    _companyNameController.dispose();
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }
}
