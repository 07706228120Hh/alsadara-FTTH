/// اسم الصفحة: إعادة تعيين الصلاحيات
/// وصف الصفحة: صفحة إعادة تعيين وتحديث الصلاحيات
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PermissionResetPage extends StatefulWidget {
  const PermissionResetPage({super.key});

  @override
  State<PermissionResetPage> createState() => _PermissionResetPageState();
}

class _PermissionResetPageState extends State<PermissionResetPage> {
  bool _isResetting = false;

  final Map<String, bool> _defaultPermissions = {
    'users': true,
    'subscriptions': true,
    'tasks': true,
    'zones': true,
    'accounts': true,
    'export': true,
    'agents': true,
    'google_sheets': true,
    'whatsapp': true,
  };

  Future<void> _resetPermissions() async {
    setState(() {
      _isResetting = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();

      // حذف جميع الصلاحيات المحفوظة القديمة
      for (String key in _defaultPermissions.keys) {
        await prefs.remove('global_perm_$key');
      }

      // تعيين الصلاحيات الجديدة
      for (var entry in _defaultPermissions.entries) {
        await prefs.setBool('global_perm_${entry.key}', entry.value);
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ تم إعادة تعيين جميع الصلاحيات بنجاح!'),
          backgroundColor: Colors.green,
        ),
      );

      // العودة للصفحة السابقة
      Navigator.pop(context, true); // إرجاع true للإشارة لنجاح العملية
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ خطأ في إعادة تعيين الصلاحيات'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isResetting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إعادة تعيين الصلاحيات'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(
              Icons.settings_backup_restore,
              size: 80,
              color: Colors.orange,
            ),
            const SizedBox(height: 20),
            const Text(
              'إعادة تعيين صلاحيات النظام',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ما سيتم تفعيله:',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ..._defaultPermissions.entries.map((entry) {
                      String title = '';
                      switch (entry.key) {
                        case 'users':
                          title = '👥 إدارة المستخدمين';
                          break;
                        case 'subscriptions':
                          title = '📋 إدارة الاشتراكات';
                          break;
                        case 'tasks':
                          title = '📝 إدارة المهام';
                          break;
                        case 'zones':
                          title = '🗺️ إدارة المناطق';
                          break;
                        case 'accounts':
                          title = '💰 إدارة الحسابات';
                          break;
                        case 'export':
                          title = '📤 ترحيل البيانات للدرايف';
                          break;
                        case 'agents':
                          title = '🤝 إدارة الوكلاء';
                          break;
                        case 'google_sheets':
                          title = '📊 حفظ في الخادم';
                          break;
                        case 'whatsapp':
                          title = '💬 إرسال رسائل WhatsApp';
                          break;
                      }
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Row(
                          children: [
                            const Icon(Icons.check,
                                color: Colors.green, size: 20),
                            const SizedBox(width: 8),
                            Text(title),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: _isResetting ? null : _resetPermissions,
              icon: _isResetting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              label: Text(_isResetting
                  ? 'جاري إعادة التعيين...'
                  : 'إعادة تعيين الصلاحيات'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(fontSize: 18),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.yellow[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange[200]!),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '⚠️ ملاحظة هامة:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text('• ستحتاج لإعادة تشغيل التطبيق بعد إعادة التعيين'),
                  Text('• سيتم تفعيل جميع الأزرار والصلاحيات'),
                  Text('• يمكن تعديل الصلاحيات لاحقاً من إعدادات النظام'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
