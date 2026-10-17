/// شاشة معلومات الحساب للمستخدم
/// تعرض كل معلومات الحساب لمدير النظام أو الموظف
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../frontend/frontend.dart'; // نظام تصميم الصدارة الموحّد (sd)
import '../../services/vps_auth_service.dart';
import '../../services/custom_auth_service.dart';
import '../../config/data_source_config.dart';

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
          _errorMessage = 'حدث خطأ'.replaceAll('Exception: ', '');
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
      return SdPage(
        appBar: const SdAppBar(title: 'حسابي'),
        body: const SdEmptyState(
          icon: Icons.account_circle_outlined,
          title: 'لم يتم تسجيل الدخول بعد',
        ),
      );
    }

    final isPhone = context.sd.isPhone;
    final leftColumn = Column(
      children: [
        _buildInfoCard(
          title: 'معلومات الحساب',
          icon: Icons.person,
          tone: SdStatus.info.tone,
          items: [
            _InfoItem('معرف الحساب', _userId, Icons.fingerprint),
            _InfoItem('اسم المستخدم', _username, Icons.account_circle),
            _InfoItem('الاسم الكامل', _fullName, Icons.badge),
            if (_email.isNotEmpty)
              _InfoItem('البريد الإلكتروني', _email, Icons.email),
            if (_phone.isNotEmpty) _InfoItem('رقم الهاتف', _phone, Icons.phone),
          ],
        ),
        const SizedBox(height: 16),
        _buildInfoCard(
          title: 'الصلاحيات والدور',
          icon: Icons.security,
          tone: SdGroup.platform.tone,
          items: [
            _InfoItem('الدور', _role, Icons.admin_panel_settings),
            _InfoItem('الحالة', _isActive ? 'نشط' : 'غير نشط',
                _isActive ? Icons.check_circle : Icons.cancel),
            if (_isSuperAdmin)
              _InfoItem('نوع الحساب', 'مدير النظام الرئيسي', Icons.shield),
          ],
        ),
      ],
    );
    final rightColumn = Column(
      children: [
        _buildInfoCard(
          title: 'معلومات الجلسة',
          icon: Icons.vpn_key,
          tone: SdStatus.warning.tone,
          items: [
            if (_lastLogin != null)
              _InfoItem('آخر دخول', _formatDateTime(_lastLogin!), Icons.login),
            if (_tokenExpiry != null)
              _InfoItem(
                  'انتهاء الجلسة', _formatDateTime(_tokenExpiry!), Icons.timer),
            _InfoItem('حالة الجلسة', _token.isNotEmpty ? 'نشطة' : 'غير نشطة',
                Icons.wifi),
          ],
        ),
        const SizedBox(height: 16),
        if (_token.isNotEmpty) _buildTokenCard(),
      ],
    );

    return SdPage(
      appBar: SdAppBar(
        title: 'معلومات الحساب',
        actions: [
          SdAppBarAction(
            icon: Icons.refresh,
            label: 'تحديث',
            onPressed: _loadUserData,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_errorMessage != null) _buildMessageBox(_errorMessage!, true),
          if (_successMessage != null) _buildMessageBox(_successMessage!, false),

          // بطاقة المعلومات الرئيسية
          _buildProfileCard(),

          const SizedBox(height: 16),

          // بطاقات المعلومات
          if (isPhone) ...[
            leftColumn,
            const SizedBox(height: 16),
            rightColumn,
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: leftColumn),
                const SizedBox(width: 16),
                Expanded(child: rightColumn),
              ],
            ),

          const SizedBox(height: 16),

          if (!_isSuperAdmin && _permissions.isNotEmpty) _buildPermissionsCard(),

          const SizedBox(height: 16),

          // قسم التعديل - فقط للموظفين وليس لـ SuperAdmin
          if (!_isSuperAdmin) _buildEditCard(),

          // ملاحظة للـ SuperAdmin
          if (_isSuperAdmin)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: SdColors.warningTint,
                borderRadius: BorderRadius.circular(SdRadius.sm),
                border: Border.all(color: SdColors.warningTintEdge),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      color: SdColors.warning, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'لتعديل بيانات مدير النظام، استخدم صفحة إدارة قاعدة البيانات',
                      style: SdText.bodySm
                          .copyWith(color: SdColors.warningText, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProfileCard() {
    final gradient = _isSuperAdmin
        ? const LinearGradient(
            colors: [Color(0xFF7B1FA2), Color(0xFF4A148C)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : const LinearGradient(
            colors: [SdColors.primaryMid, SdColors.primary],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          );
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(SdRadius.md),
        boxShadow: [
          BoxShadow(
            color: (_isSuperAdmin ? const Color(0xFF4A148C) : SdColors.primary)
                .withValues(alpha: 0.3),
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
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(SdRadius.md),
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
                    fontFamily: SdText.family,
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '@$_username',
                  style: TextStyle(
                      fontFamily: SdText.family,
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 14),
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(SdRadius.lg),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_isSuperAdmin ? Icons.shield : Icons.work,
                          color: Colors.white, size: 14),
                      const SizedBox(width: 6),
                      Text(_role,
                          style: const TextStyle(
                              fontFamily: SdText.family,
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w800)),
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
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(SdRadius.sm),
                ),
                child: Icon(_isActive ? Icons.verified : Icons.warning,
                    color: Colors.white, size: 24),
              ),
              const SizedBox(height: 4),
              Text(_isActive ? 'نشط' : 'معطل',
                  style: TextStyle(
                      fontFamily: SdText.family,
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required String title,
    required IconData icon,
    required SdTone tone,
    required List<_InfoItem> items,
  }) {
    return SdCard(
      title: title,
      icon: icon,
      tone: tone,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          Icon(item.icon, color: SdColors.faint, size: 16),
          const SizedBox(width: 10),
          Text('${item.label}:', style: SdText.caption),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              item.value.isNotEmpty ? item.value : 'غير محدد',
              style: SdText.label.copyWith(
                color: item.value.isNotEmpty ? SdColors.ink : SdColors.muted,
                fontSize: 13,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 14),
            color: SdColors.faint,
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
    return SdCard(
      title: 'رمز الجلسة (Token)',
      icon: Icons.key,
      tone: SdStatus.success.tone,
      trailing: IconButton(
        icon: const Icon(Icons.copy, size: 18),
        color: SdColors.faint,
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
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: SdColors.surfaceAlt,
            borderRadius: BorderRadius.circular(SdRadius.xs)),
        child: SelectableText(shortToken,
            style: SdText.mono.copyWith(fontSize: 11.5)),
      ),
    );
  }

  Widget _buildPermissionsCard() {
    return SdCard(
      title: 'الصلاحيات الممنوحة',
      icon: Icons.list_alt,
      tone: SdGroup.field.tone,
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
            color: SdColors.accentTint,
            borderRadius: BorderRadius.circular(SdRadius.sm)),
        child: Text('${_permissions.length}',
            style: SdText.caption.copyWith(color: SdColors.accentEdge)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _permissions.map((permission) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: SdColors.surfaceAlt,
              borderRadius: BorderRadius.circular(SdRadius.xs),
              border: Border.all(color: SdColors.divider),
            ),
            child: Text(permission,
                style: SdText.caption.copyWith(color: SdColors.ink)),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildEditCard() {
    return SdCard(
      title: 'تعديل البيانات',
      icon: Icons.edit,
      tone: SdGroup.admin.tone,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildEditableField(
              controller: _usernameController,
              label: 'اسم المستخدم',
              icon: Icons.account_circle),
          const SizedBox(height: 16),
          _buildPasswordField(),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: _isSaving
                ? const SdButton(
                    label: 'جاري الحفظ...',
                    icon: Icons.hourglass_top,
                    onPressed: null,
                    expand: true,
                  )
                : SdButton(
                    label: 'حفظ التغييرات',
                    icon: Icons.save,
                    expand: true,
                    onPressed: _saveChanges,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBox(String message, bool isError) {
    final tone = (isError ? SdStatus.danger : SdStatus.success).tone;
    return Container(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: tone.tint,
        borderRadius: BorderRadius.circular(SdRadius.xs),
        border: Border.all(color: tone.tintEdge),
      ),
      child: Row(
        children: [
          Icon(isError ? Icons.error_outline : Icons.check_circle_outline,
              color: tone.base, size: 20),
          const SizedBox(width: 10),
          Expanded(
              child: Text(message,
                  style: SdText.bodySm.copyWith(color: tone.text, fontSize: 13))),
          IconButton(
            icon: Icon(Icons.close, color: tone.base, size: 18),
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
        Text(label, style: SdText.caption),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          style: SdText.label.copyWith(fontSize: 14),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: SdColors.faint, size: 20),
            filled: true,
            fillColor: SdColors.surfaceAlt,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(SdRadius.xs),
                borderSide: const BorderSide(color: SdColors.divider)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(SdRadius.xs),
                borderSide: const BorderSide(color: SdColors.divider)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(SdRadius.xs),
                borderSide: const BorderSide(color: SdColors.primary)),
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('كلمة المرور الجديدة', style: SdText.caption),
        const SizedBox(height: 6),
        TextField(
          controller: _passwordController,
          obscureText: !_showPassword,
          style: SdText.label.copyWith(fontSize: 14),
          decoration: InputDecoration(
            hintText: 'اتركه فارغاً لعدم التغيير',
            hintStyle: SdText.caption,
            prefixIcon: const Icon(Icons.lock, color: SdColors.faint, size: 20),
            suffixIcon: IconButton(
              icon: Icon(
                  _showPassword ? Icons.visibility : Icons.visibility_off,
                  color: SdColors.faint,
                  size: 20),
              onPressed: () => setState(() => _showPassword = !_showPassword),
            ),
            filled: true,
            fillColor: SdColors.surfaceAlt,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(SdRadius.xs),
                borderSide: const BorderSide(color: SdColors.divider)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(SdRadius.xs),
                borderSide: const BorderSide(color: SdColors.divider)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(SdRadius.xs),
                borderSide: const BorderSide(color: SdColors.primary)),
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
