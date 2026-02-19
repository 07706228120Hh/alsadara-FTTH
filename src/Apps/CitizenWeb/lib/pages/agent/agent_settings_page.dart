import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../providers/agent_auth_provider.dart';
import '../../services/agent_api_service.dart';

/// صفحة إعدادات الوكيل - عرض البيانات + تغيير كلمة المرور + تسجيل الخروج
class AgentSettingsPage extends StatefulWidget {
  const AgentSettingsPage({super.key});

  @override
  State<AgentSettingsPage> createState() => _AgentSettingsPageState();
}

class _AgentSettingsPageState extends State<AgentSettingsPage> {
  AgentData? _agent;
  bool _isChangingPassword = false;
  bool _isLoading = false;

  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _passwordFormKey = GlobalKey<FormState>();
  bool _showCurrentPassword = false;
  bool _showNewPassword = false;

  @override
  void initState() {
    super.initState();
    _loadAgent();
  }

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _loadAgent() {
    final agentAuth = context.read<AgentAuthProvider>();
    setState(() => _agent = agentAuth.agent);
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('تسجيل الخروج'),
        content: const Text('هل أنت متأكد من تسجيل الخروج؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorColor,
            ),
            child: const Text(
              'تسجيل الخروج',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final agentAuth = context.read<AgentAuthProvider>();
      await agentAuth.logout();
      if (mounted) context.go('/agent/login');
    }
  }

  Future<void> _changePassword() async {
    if (!_passwordFormKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final agentAuth = context.read<AgentAuthProvider>();
      await agentAuth.agentApi.changePassword(
        currentPassword: _currentPasswordController.text,
        newPassword: _newPasswordController.text,
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
          _isChangingPassword = false;
        });
        _currentPasswordController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تغيير كلمة المرور بنجاح'),
            backgroundColor: AppTheme.successColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.agentTheme,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: AppTheme.backgroundColor,
          appBar: AppBar(
            title: const Text('الإعدادات'),
            centerTitle: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_forward_ios, size: 20),
              onPressed: () => context.go('/agent/home'),
            ),
          ),
          body: _agent == null
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      // بطاقة الملف الشخصي
                      _buildProfileCard(),
                      const SizedBox(height: 24),

                      // معلومات الحساب
                      _buildAccountInfo(),
                      const SizedBox(height: 24),

                      // تغيير كلمة المرور
                      _buildPasswordSection(),
                      const SizedBox(height: 24),

                      // معلومات الرصيد
                      _buildBalanceInfo(),
                      const SizedBox(height: 32),

                      // تسجيل الخروج
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _logout,
                          icon: const Icon(
                            Icons.logout,
                            color: AppTheme.errorColor,
                          ),
                          label: const Text(
                            'تسجيل الخروج',
                            style: TextStyle(color: AppTheme.errorColor),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: const BorderSide(color: AppTheme.errorColor),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // إصدار التطبيق
                      Text(
                        'إصدار بوابة الوكيل 1.0.0',
                        style: TextStyle(color: Colors.grey[400], fontSize: 12),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildProfileCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.agentColor, Color(0xFF0D47A1)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: Colors.white.withOpacity(0.2),
            child: Text(
              _agent!.name.isNotEmpty ? _agent!.name[0] : '?',
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _agent!.name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'كود: ${_agent!.agentCode}',
              style: const TextStyle(color: Colors.white70),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: _agent!.status == 0
                  ? AppTheme.successColor.withOpacity(0.3)
                  : AppTheme.errorColor.withOpacity(0.3),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _agent!.statusName,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountInfo() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('معلومات الحساب', style: AppTheme.headingSmall),
          const SizedBox(height: 16),
          _buildInfoRow(Icons.phone, 'رقم الهاتف', _agent!.phoneNumber),
          _buildInfoRow(Icons.category, 'نوع الوكيل', _agent!.typeName),
          if (_agent!.city != null)
            _buildInfoRow(Icons.location_city, 'المدينة', _agent!.city!),
          if (_agent!.area != null)
            _buildInfoRow(Icons.place, 'المنطقة', _agent!.area!),
          if (_agent!.companyName != null)
            _buildInfoRow(Icons.business, 'الشركة', _agent!.companyName!),
          _buildInfoRow(
            Icons.calendar_today,
            'تاريخ التسجيل',
            '${_agent!.createdAt.year}/${_agent!.createdAt.month}/${_agent!.createdAt.day}',
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppTheme.agentColor),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(color: AppTheme.textGrey)),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: AppTheme.textDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('كلمة المرور', style: AppTheme.headingSmall),
              TextButton.icon(
                onPressed: () =>
                    setState(() => _isChangingPassword = !_isChangingPassword),
                icon: Icon(
                  _isChangingPassword ? Icons.close : Icons.edit,
                  size: 18,
                ),
                label: Text(_isChangingPassword ? 'إلغاء' : 'تغيير'),
              ),
            ],
          ),
          if (_isChangingPassword) ...[
            const SizedBox(height: 16),
            Form(
              key: _passwordFormKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _currentPasswordController,
                    obscureText: !_showCurrentPassword,
                    decoration: InputDecoration(
                      labelText: 'كلمة المرور الحالية',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _showCurrentPassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () => setState(
                          () => _showCurrentPassword = !_showCurrentPassword,
                        ),
                      ),
                    ),
                    validator: (v) => (v == null || v.isEmpty)
                        ? 'أدخل كلمة المرور الحالية'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _newPasswordController,
                    obscureText: !_showNewPassword,
                    decoration: InputDecoration(
                      labelText: 'كلمة المرور الجديدة',
                      prefixIcon: const Icon(Icons.lock),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _showNewPassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () => setState(
                          () => _showNewPassword = !_showNewPassword,
                        ),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) {
                        return 'أدخل كلمة المرور الجديدة';
                      }
                      if (v.length < 6) {
                        return 'كلمة المرور يجب أن تكون 6 أحرف على الأقل';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _confirmPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'تأكيد كلمة المرور الجديدة',
                      prefixIcon: Icon(Icons.lock),
                    ),
                    validator: (v) {
                      if (v != _newPasswordController.text) {
                        return 'كلمات المرور غير متطابقة';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _changePassword,
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('تغيير كلمة المرور'),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            const SizedBox(height: 8),
            const Text(
              '••••••••',
              style: TextStyle(
                fontSize: 18,
                letterSpacing: 4,
                color: AppTheme.textGrey,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBalanceInfo() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('معلومات مالية', style: AppTheme.headingSmall),
          const SizedBox(height: 16),
          _buildFinanceRow(
            'إجمالي الشحن',
            _agent!.totalCharges,
            Icons.arrow_downward,
            AppTheme.successColor,
          ),
          _buildFinanceRow(
            'إجمالي السداد',
            _agent!.totalPayments,
            Icons.arrow_upward,
            AppTheme.errorColor,
          ),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'صافي الرصيد',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              Text(
                '${_agent!.netBalance.toStringAsFixed(0)} د.ع',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: _agent!.netBalance >= 0
                      ? AppTheme.successColor
                      : AppTheme.errorColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFinanceRow(
    String label,
    double value,
    IconData icon,
    Color color,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: AppTheme.textGrey)),
          const Spacer(),
          Text(
            '${value.toStringAsFixed(0)} د.ع',
            style: TextStyle(fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }
}
