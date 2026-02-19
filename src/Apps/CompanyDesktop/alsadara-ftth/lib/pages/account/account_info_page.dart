/// شاشة معلومات الحساب للمستخدم
/// تعرض كل معلومات الحساب لمدير النظام أو الموظف
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/vps_auth_service.dart';
import '../../services/custom_auth_service.dart';
import '../../config/data_source_config.dart';
import '../../theme/energy_dashboard_theme.dart';

class AccountInfoPage extends StatefulWidget {
  const AccountInfoPage({super.key});

  @override
  State<AccountInfoPage> createState() => _AccountInfoPageState();
}

class _AccountInfoPageState extends State<AccountInfoPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isSaving = false;
  bool _showPassword = false;
  String? _errorMessage;
  String? _successMessage;

  // بيانات المستخدم الكاملة
  String _userId = '';
  String _fullName = '';
  String _username = '';
  String _email = '';
  String _phone = '';
  String _role = '';
  String _token = '';
  bool _isSuperAdmin = false;
  bool _isLoggedIn = false;
  bool _isActive = true;
  List<String> _permissions = [];
  DateTime? _lastLogin;
  DateTime? _tokenExpiry;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  void _loadUserData() {
    if (DataSourceConfig.useVpsApi) {
      final userType = VpsAuthService.instance.currentUserType;

      if (userType == VpsAuthUserType.superAdmin) {
        final admin = VpsAuthService.instance.currentSuperAdmin;
        if (admin != null) {
          setState(() {
            _isLoggedIn = true;
            _isSuperAdmin = true;
            _userId = admin.id;
            _fullName = admin.fullName;
            _username = admin.username;
            _email = admin.email ?? '';
            _usernameController.text = admin.username;
            _role = 'مدير النظام';
            _token = VpsAuthService.instance.accessToken ?? '';
            _lastLogin = DateTime.now();
            _tokenExpiry = DateTime.now().add(const Duration(hours: 24));
          });
        }
      } else if (userType == VpsAuthUserType.companyEmployee) {
        final user = VpsAuthService.instance.currentUser;
        if (user != null) {
          setState(() {
            _isLoggedIn = true;
            _isSuperAdmin = false;
            _userId = user.id;
            _fullName = user.fullName;
            _username = user.username;
            _email = user.email ?? '';
            _phone = user.phone ?? '';
            _usernameController.text = user.username;
            _role = _getRoleName(user.role);
            _isActive = user.isActive;
            _permissions = user.permissions;
            _token = VpsAuthService.instance.accessToken ?? '';
          });
        }
      }
    } else {
      final userType = CustomAuthService.currentUserType;

      if (userType == AuthUserType.superAdmin) {
        final admin = CustomAuthService.currentSuperAdmin;
        if (admin != null) {
          setState(() {
            _isLoggedIn = true;
            _isSuperAdmin = true;
            _userId = admin.id.toString();
            _fullName = admin.name;
            _username = admin.username;
            _usernameController.text = admin.username;
            _role = 'مدير النظام';
          });
        }
      } else {
        final user = CustomAuthService.currentUser;
        if (user != null) {
          setState(() {
            _isLoggedIn = true;
            _isSuperAdmin = false;
            _userId = user.id.toString();
            _fullName = user.fullName;
            _username = user.username;
            _usernameController.text = user.username;
            _role = _getTenantRoleName(user.role);
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    if (_usernameController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'اسم المستخدم مطلوب');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final profileResult = await VpsAuthService.instance.updateProfile(
        username: _usernameController.text.trim(),
      );

      if (profileResult['success'] != true) {
        throw Exception(profileResult['message'] ?? 'فشل تحديث اسم المستخدم');
      }

      if (_passwordController.text.isNotEmpty) {
        if (_passwordController.text.length < 6) {
          throw Exception('كلمة المرور يجب أن تكون 6 أحرف على الأقل');
        }

        final passwordResult = await VpsAuthService.instance.changePassword(
          currentPassword: '',
          newPassword: _passwordController.text,
        );

        if (passwordResult['success'] != true) {
          throw Exception(passwordResult['message'] ?? 'فشل تغيير كلمة المرور');
        }
      }

      if (mounted) {
        setState(() {
          _successMessage = 'تم حفظ التغييرات بنجاح';
          _passwordController.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoggedIn) {
      return Scaffold(
        backgroundColor: EnergyDashboardTheme.backgroundColor,
        appBar: AppBar(
          title: const Text('حسابي'),
          backgroundColor: EnergyDashboardTheme.surfaceColor,
          foregroundColor: EnergyDashboardTheme.textPrimary,
          elevation: 0,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.account_circle_outlined,
                size: 80,
                color: EnergyDashboardTheme.textMuted.withOpacity(0.5),
              ),
              const SizedBox(height: 16),
              const Text(
                'لم يتم تسجيل الدخول بعد',
                style: TextStyle(
                    color: EnergyDashboardTheme.textMuted, fontSize: 18),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: EnergyDashboardTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('معلومات الحساب'),
        backgroundColor: EnergyDashboardTheme.surfaceColor,
        foregroundColor: EnergyDashboardTheme.textPrimary,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadUserData,
            tooltip: 'تحديث',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_errorMessage != null) _buildMessageBox(_errorMessage!, true),
            if (_successMessage != null)
              _buildMessageBox(_successMessage!, false),

            // بطاقة المعلومات الرئيسية
            _buildProfileCard(),

            const SizedBox(height: 16),

            // بطاقات المعلومات
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    children: [
                      _buildInfoCard(
                        title: 'معلومات الحساب',
                        icon: Icons.person,
                        color: Colors.blue,
                        items: [
                          _InfoItem('معرف الحساب', _userId, Icons.fingerprint),
                          _InfoItem(
                              'اسم المستخدم', _username, Icons.account_circle),
                          _InfoItem('الاسم الكامل', _fullName, Icons.badge),
                          if (_email.isNotEmpty)
                            _InfoItem('البريد الإلكتروني', _email, Icons.email),
                          if (_phone.isNotEmpty)
                            _InfoItem('رقم الهاتف', _phone, Icons.phone),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildInfoCard(
                        title: 'الصلاحيات والدور',
                        icon: Icons.security,
                        color: Colors.purple,
                        items: [
                          _InfoItem('الدور', _role, Icons.admin_panel_settings),
                          _InfoItem('الحالة', _isActive ? 'نشط' : 'غير نشط',
                              _isActive ? Icons.check_circle : Icons.cancel),
                          if (_isSuperAdmin)
                            _InfoItem('نوع الحساب', 'مدير النظام الرئيسي',
                                Icons.shield),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    children: [
                      _buildInfoCard(
                        title: 'معلومات الجلسة',
                        icon: Icons.vpn_key,
                        color: Colors.orange,
                        items: [
                          if (_lastLogin != null)
                            _InfoItem('آخر دخول', _formatDateTime(_lastLogin!),
                                Icons.login),
                          if (_tokenExpiry != null)
                            _InfoItem('انتهاء الجلسة',
                                _formatDateTime(_tokenExpiry!), Icons.timer),
                          _InfoItem(
                              'حالة الجلسة',
                              _token.isNotEmpty ? 'نشطة' : 'غير نشطة',
                              Icons.wifi),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (_token.isNotEmpty) _buildTokenCard(),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            if (!_isSuperAdmin && _permissions.isNotEmpty)
              _buildPermissionsCard(),

            const SizedBox(height: 16),

            // قسم التعديل - فقط للموظفين وليس لـ SuperAdmin
            if (!_isSuperAdmin) _buildEditCard(),

            // ملاحظة للـ SuperAdmin
            if (_isSuperAdmin)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange, size: 20),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'لتعديل بيانات مدير النظام، استخدم صفحة إدارة قاعدة البيانات',
                        style: TextStyle(color: Colors.orange, fontSize: 13),
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

  Widget _buildProfileCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _isSuperAdmin
              ? [Colors.purple.shade700, Colors.deepPurple.shade900]
              : [
                  EnergyDashboardTheme.primaryColor,
                  EnergyDashboardTheme.accentColor
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: (_isSuperAdmin
                    ? Colors.purple
                    : EnergyDashboardTheme.primaryColor)
                .withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              _isSuperAdmin ? Icons.admin_panel_settings : Icons.person,
              color: Colors.white,
              size: 40,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _fullName.isNotEmpty ? _fullName : _username,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '@$_username',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.8), fontSize: 14),
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_isSuperAdmin ? Icons.shield : Icons.work,
                          color: Colors.white, size: 14),
                      const SizedBox(width: 6),
                      Text(_role,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Column(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_isActive ? Icons.verified : Icons.warning,
                    color: Colors.white, size: 24),
              ),
              const SizedBox(height: 4),
              Text(_isActive ? 'نشط' : 'معطل',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.9), fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required String title,
    required IconData icon,
    required Color color,
    required List<_InfoItem> items,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: EnergyDashboardTheme.surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: EnergyDashboardTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 10),
              Text(title,
                  style: const TextStyle(
                      color: EnergyDashboardTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          const Divider(height: 20),
          ...items.map((item) => _buildInfoRow(item)),
        ],
      ),
    );
  }

  Widget _buildInfoRow(_InfoItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(item.icon, color: EnergyDashboardTheme.textMuted, size: 16),
          const SizedBox(width: 10),
          Text('${item.label}:',
              style: const TextStyle(
                  color: EnergyDashboardTheme.textMuted, fontSize: 12)),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              item.value.isNotEmpty ? item.value : 'غير محدد',
              style: TextStyle(
                color: item.value.isNotEmpty
                    ? EnergyDashboardTheme.textPrimary
                    : EnergyDashboardTheme.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 14),
            color: EnergyDashboardTheme.textMuted,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: item.value));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text('تم نسخ ${item.label}'),
                    duration: const Duration(seconds: 1)),
              );
            },
            tooltip: 'نسخ',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
        ],
      ),
    );
  }

  Widget _buildTokenCard() {
    final shortToken =
        _token.length > 50 ? '${_token.substring(0, 50)}...' : _token;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: EnergyDashboardTheme.surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: EnergyDashboardTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.key, color: Colors.green, size: 18),
              ),
              const SizedBox(width: 10),
              const Text('رمز الجلسة (Token)',
                  style: TextStyle(
                      color: EnergyDashboardTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                color: EnergyDashboardTheme.textMuted,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _token));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('تم نسخ Token'),
                        duration: Duration(seconds: 1)),
                  );
                },
                tooltip: 'نسخ Token كامل',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: EnergyDashboardTheme.backgroundColor,
                borderRadius: BorderRadius.circular(8)),
            child: SelectableText(shortToken,
                style: const TextStyle(
                    color: EnergyDashboardTheme.textMuted,
                    fontSize: 11,
                    fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: EnergyDashboardTheme.surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: EnergyDashboardTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: Colors.teal.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.list_alt, color: Colors.teal, size: 18),
              ),
              const SizedBox(width: 10),
              const Text('الصلاحيات الممنوحة',
                  style: TextStyle(
                      color: EnergyDashboardTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: Colors.teal.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12)),
                child: Text('${_permissions.length}',
                    style: const TextStyle(
                        color: Colors.teal,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _permissions.map((permission) {
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: EnergyDashboardTheme.backgroundColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: EnergyDashboardTheme.borderColor),
                ),
                child: Text(permission,
                    style: const TextStyle(
                        color: EnergyDashboardTheme.textPrimary, fontSize: 11)),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildEditCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: EnergyDashboardTheme.surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: EnergyDashboardTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: Colors.indigo.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.edit, color: Colors.indigo, size: 18),
              ),
              const SizedBox(width: 10),
              const Text('تعديل البيانات',
                  style: TextStyle(
                      color: EnergyDashboardTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          const Divider(height: 24),
          _buildEditableField(
              controller: _usernameController,
              label: 'اسم المستخدم',
              icon: Icons.account_circle),
          const SizedBox(height: 16),
          _buildPasswordField(),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _saveChanges,
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save, size: 18),
              label: Text(_isSaving ? 'جاري الحفظ...' : 'حفظ التغييرات'),
              style: ElevatedButton.styleFrom(
                backgroundColor: EnergyDashboardTheme.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBox(String message, bool isError) {
    return Container(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: (isError ? Colors.red : Colors.green).withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: (isError ? Colors.red : Colors.green).withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(isError ? Icons.error_outline : Icons.check_circle_outline,
              color: isError ? Colors.red : Colors.green, size: 20),
          const SizedBox(width: 10),
          Expanded(
              child: Text(message,
                  style: TextStyle(
                      color: isError ? Colors.red : Colors.green,
                      fontSize: 13))),
          IconButton(
            icon: Icon(Icons.close,
                color: isError ? Colors.red : Colors.green, size: 18),
            onPressed: () => setState(() {
              if (isError) {
                _errorMessage = null;
              } else {
                _successMessage = null;
              }
            }),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
        ],
      ),
    );
  }

  Widget _buildEditableField(
      {required TextEditingController controller,
      required String label,
      required IconData icon}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: EnergyDashboardTheme.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          style: const TextStyle(
              color: EnergyDashboardTheme.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            prefixIcon:
                Icon(icon, color: EnergyDashboardTheme.textMuted, size: 20),
            filled: true,
            fillColor: EnergyDashboardTheme.backgroundColor,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    const BorderSide(color: EnergyDashboardTheme.borderColor)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    const BorderSide(color: EnergyDashboardTheme.borderColor)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    const BorderSide(color: EnergyDashboardTheme.primaryColor)),
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('كلمة المرور الجديدة',
            style:
                TextStyle(color: EnergyDashboardTheme.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        TextField(
          controller: _passwordController,
          obscureText: !_showPassword,
          style: const TextStyle(
              color: EnergyDashboardTheme.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'اتركه فارغاً لعدم التغيير',
            hintStyle: const TextStyle(
                color: EnergyDashboardTheme.textMuted, fontSize: 12),
            prefixIcon: const Icon(Icons.lock,
                color: EnergyDashboardTheme.textMuted, size: 20),
            suffixIcon: IconButton(
              icon: Icon(
                  _showPassword ? Icons.visibility : Icons.visibility_off,
                  color: EnergyDashboardTheme.textMuted,
                  size: 20),
              onPressed: () => setState(() => _showPassword = !_showPassword),
            ),
            filled: true,
            fillColor: EnergyDashboardTheme.backgroundColor,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    const BorderSide(color: EnergyDashboardTheme.borderColor)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    const BorderSide(color: EnergyDashboardTheme.borderColor)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    const BorderSide(color: EnergyDashboardTheme.primaryColor)),
          ),
        ),
      ],
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  String _getRoleName(String role) {
    switch (role.toLowerCase()) {
      case 'superadmin':
        return 'مدير النظام';
      case 'companyadmin':
        return 'مدير الشركة';
      case 'manager':
        return 'مدير';
      case 'technician':
        return 'فني';
      case 'employee':
        return 'موظف';
      case 'citizen':
        return 'مواطن';
      default:
        return role;
    }
  }

  String _getTenantRoleName(dynamic role) {
    if (role == null) return 'موظف';
    final roleStr = role.toString().toLowerCase();
    if (roleStr.contains('admin') || roleStr.contains('companyAdmin'))
      return 'مدير الشركة';
    if (roleStr.contains('manager')) return 'مدير';
    if (roleStr.contains('technician')) return 'فني';
    if (roleStr.contains('employee')) return 'موظف';
    return role.toString();
  }
}

class _InfoItem {
  final String label;
  final String value;
  final IconData icon;
  _InfoItem(this.label, this.value, this.icon);
}
