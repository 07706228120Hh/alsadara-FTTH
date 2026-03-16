/// صفحة إعدادات الشركة (Firebase)
/// تدير اسم المدير ورقم واتساب المدير وإعدادات التقارير
library;

import 'package:flutter/material.dart';
import '../../services/company_settings_service.dart';

class CompanyFirebaseSettingsPage extends StatefulWidget {
  const CompanyFirebaseSettingsPage({super.key});

  @override
  State<CompanyFirebaseSettingsPage> createState() =>
      _CompanyFirebaseSettingsPageState();
}

class _CompanyFirebaseSettingsPageState
    extends State<CompanyFirebaseSettingsPage> {
  bool _isLoading = true;
  bool _isSaving = false;
  CompanySettings _settings = CompanySettings();

  final _managerNameCtrl = TextEditingController();
  final _managerWhatsAppCtrl = TextEditingController();

  late bool _receiveReports;
  late bool _bulkSendReport;
  late bool _dailyReport;
  late bool _weeklyReport;

  @override
  void initState() {
    super.initState();
    _receiveReports = true;
    _bulkSendReport = true;
    _dailyReport = false;
    _weeklyReport = false;
    _loadSettings();
  }

  @override
  void dispose() {
    _managerNameCtrl.dispose();
    _managerWhatsAppCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    try {
      final settings = await CompanySettingsService.getSettings();
      if (mounted) {
        setState(() {
          _settings = settings;
          _managerNameCtrl.text = settings.managerName ?? '';
          _managerWhatsAppCtrl.text = settings.managerWhatsApp ?? '';
          _receiveReports = settings.receiveReports;
          _bulkSendReport = settings.bulkSendReport;
          _dailyReport = settings.dailyReport;
          _weeklyReport = settings.weeklyReport;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnack('فشل تحميل الإعدادات', isError: true);
      }
    }
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      final updated = CompanySettings(
        managerName: _managerNameCtrl.text.trim().isEmpty
            ? null
            : _managerNameCtrl.text.trim(),
        managerWhatsApp: _managerWhatsAppCtrl.text.trim().isEmpty
            ? null
            : _managerWhatsAppCtrl.text.trim(),
        receiveReports: _receiveReports,
        bulkSendReport: _bulkSendReport,
        dailyReport: _dailyReport,
        weeklyReport: _weeklyReport,
      );

      final ok = await CompanySettingsService.saveSettings(updated);
      if (mounted) {
        setState(() => _isSaving = false);
        if (ok) {
          _showSnack('تم الحفظ بنجاح');
        } else {
          _showSnack('فشل في الحفظ', isError: true);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        _showSnack('خطأ', isError: true);
      }
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, textAlign: TextAlign.right),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إعدادات الشركة',
              style: TextStyle(fontWeight: FontWeight.bold)),
          centerTitle: true,
          backgroundColor: const Color(0xFF455A64),
          foregroundColor: Colors.white,
          elevation: 2,
          actions: [
            if (!_isLoading)
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadSettings,
                tooltip: 'تحديث',
              ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildManagerSection(),
                  const SizedBox(height: 16),
                  _buildReportsSection(),
                  const SizedBox(height: 24),
                  _buildSaveButton(),
                  if (_settings.updatedAt != null) ...[
                    const SizedBox(height: 12),
                    Center(
                      child: Text(
                        'آخر تحديث: ${_formatDate(_settings.updatedAt!)}',
                        style: TextStyle(
                            color: Colors.grey[500], fontSize: 12),
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _buildManagerSection() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.person, color: Color(0xFF455A64)),
                const SizedBox(width: 8),
                const Text('معلومات المدير',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(height: 24),
            TextField(
              controller: _managerNameCtrl,
              decoration: InputDecoration(
                labelText: 'اسم المدير',
                prefixIcon: const Icon(Icons.badge_outlined),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _managerWhatsAppCtrl,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'رقم واتساب المدير',
                hintText: '07xxxxxxxxx',
                prefixIcon: const Icon(Icons.phone, color: Colors.green),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportsSection() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.assessment, color: Colors.orange),
                const SizedBox(width: 8),
                const Text('إعدادات التقارير',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(height: 24),
            SwitchListTile(
              title: const Text('استلام التقارير'),
              subtitle:
                  const Text('تفعيل أو تعطيل إرسال التقارير للمدير'),
              value: _receiveReports,
              onChanged: (v) => setState(() => _receiveReports = v),
              activeColor: Colors.green,
            ),
            if (_receiveReports) ...[
              const Divider(),
              SwitchListTile(
                title: const Text('تقرير الإرسال الجماعي'),
                subtitle: const Text(
                    'إرسال تقرير بعد كل عملية إرسال جماعي'),
                value: _bulkSendReport,
                onChanged: (v) => setState(() => _bulkSendReport = v),
                activeColor: Colors.blue,
              ),
              SwitchListTile(
                title: const Text('تقرير يومي'),
                subtitle: const Text('ملخص يومي للعمليات'),
                value: _dailyReport,
                onChanged: (v) => setState(() => _dailyReport = v),
                activeColor: Colors.blue,
              ),
              SwitchListTile(
                title: const Text('تقرير أسبوعي'),
                subtitle: const Text('ملخص أسبوعي للعمليات'),
                value: _weeklyReport,
                onChanged: (v) => setState(() => _weeklyReport = v),
                activeColor: Colors.blue,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        onPressed: _isSaving ? null : _save,
        icon: _isSaving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.save),
        label: Text(_isSaving ? 'جاري الحفظ...' : 'حفظ الإعدادات'),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF455A64),
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}
