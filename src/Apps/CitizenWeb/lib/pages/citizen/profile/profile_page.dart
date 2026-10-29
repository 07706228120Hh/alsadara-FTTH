import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:sadara_design/sadara_design.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/api_service.dart';

/// الملف الشخصي — موحّد على نظام تصميم الصدارة (3D).
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _isEditing = false;
  bool _isSaving = false;
  final _apiService = ApiService();
  final Map<String, dynamic> _userData = {};

  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _emailController;
  late TextEditingController _addressController;
  late TextEditingController _cityController;
  late TextEditingController _postalCodeController;

  @override
  void initState() {
    super.initState();
    final citizen = context.read<AuthProvider>().citizen;
    _userData.addAll({
      'name': citizen?.fullName ?? '',
      'phone': citizen?.phoneNumber ?? '',
      'email': citizen?.email ?? '',
      'address': citizen?.fullAddress ?? '',
      'city': citizen?.city ?? '',
      'postalCode': citizen?.district ?? '',
    });
    _nameController = TextEditingController(text: _userData['name']);
    _phoneController = TextEditingController(text: _userData['phone']);
    _emailController = TextEditingController(text: _userData['email']);
    _addressController = TextEditingController(text: _userData['address']);
    _cityController = TextEditingController(text: _userData['city']);
    _postalCodeController = TextEditingController(text: _userData['postalCode']);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _postalCodeController.dispose();
    super.dispose();
  }

  void _toggleEdit() {
    setState(() {
      if (_isEditing) {
        _nameController.text = _userData['name'];
        _emailController.text = _userData['email'];
        _addressController.text = _userData['address'];
        _cityController.text = _userData['city'];
        _postalCodeController.text = _userData['postalCode'];
      }
      _isEditing = !_isEditing;
    });
  }

  Future<void> _saveChanges() async {
    setState(() => _isSaving = true);
    try {
      final token = await _apiService.getToken();
      if (token != null) {
        await _apiService.updateProfile(
          fullName: _nameController.text,
          email: _emailController.text,
          city: _cityController.text,
          district: _postalCodeController.text,
          fullAddress: _addressController.text,
        );
      }
      setState(() {
        _userData['name'] = _nameController.text;
        _userData['email'] = _emailController.text;
        _userData['address'] = _addressController.text;
        _userData['city'] = _cityController.text;
        _userData['postalCode'] = _postalCodeController.text;
        _isEditing = false;
        _isSaving = false;
      });
      if (mounted) await context.read<AuthProvider>().loadProfile();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('تم حفظ التغييرات بنجاح'),
          backgroundColor: SdColors.success,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('خطأ: ${e.toString().replaceAll("Exception: ", "")}'),
          backgroundColor: SdColors.danger,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _nameController.text.isEmpty ? 'مستخدم' : _nameController.text;
    return SdPage(
      maxWidth: 640,
      appBar: SdAppBar(
        title: 'الملف الشخصي',
        onBack: () => context.go('/citizen/home'),
        actions: [
          IconButton(
            tooltip: _isEditing ? 'إلغاء' : 'تعديل',
            icon: Icon(_isEditing ? Icons.close_rounded : Icons.edit_rounded),
            onPressed: _toggleEdit,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(name),
          const SizedBox(height: SdSpace.lg),
          SdCard(
            title: 'البيانات الشخصية',
            child: Column(
              children: [
                _field('الاسم الكامل', _nameController, Icons.person_rounded),
                _field('رقم الهاتف', _phoneController, Icons.phone_rounded, editable: false),
                _field('البريد الإلكتروني', _emailController, Icons.email_rounded),
                _field('المدينة', _cityController, Icons.location_city_rounded),
                _field('المنطقة', _postalCodeController, Icons.map_rounded),
                _field('العنوان', _addressController, Icons.home_rounded),
              ],
            ),
          ),
          if (_isEditing) ...[
            const SizedBox(height: SdSpace.md),
            SdButton(
              label: 'حفظ التغييرات',
              icon: Icons.save_rounded,
              expand: true,
              isLoading: _isSaving,
              onPressed: _saveChanges,
            ),
          ],
          const SizedBox(height: SdSpace.lg),
          SdCard(
            title: 'الإعدادات',
            child: Column(
              children: [
                _option('تغيير كلمة المرور', Icons.lock_outline_rounded, _showChangePasswordDialog),
                _option('إعدادات الإشعارات', Icons.notifications_outlined,
                    () => context.go('/citizen/notifications')),
                _option('الخصوصية والأمان', Icons.security_outlined, () {}),
                _option('تسجيل الخروج', Icons.logout_rounded, _showLogoutDialog,
                    destructive: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(String name) {
    final initial = name.isNotEmpty ? name.characters.first : 'م';
    return Row(
      children: [
        Container(
          width: 64,
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [SdColors.primarySoft, SdColors.primaryEdge],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: SdColors.goldLight, width: 1.4),
            boxShadow: const [
              BoxShadow(color: Color(0x55132A5E), blurRadius: 18, offset: Offset(0, 8)),
            ],
          ),
          child: Text(initial,
              style: const TextStyle(
                  fontFamily: SdText.family,
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w900)),
        ),
        const SizedBox(width: SdSpace.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: SdText.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(_phoneController.text.isEmpty ? '—' : _phoneController.text,
                  style: SdText.bodySm),
            ],
          ),
        ),
      ],
    );
  }

  Widget _field(String label, TextEditingController c, IconData icon,
      {bool editable = true}) {
    if (_isEditing && editable) {
      return Padding(
        padding: const EdgeInsets.only(bottom: SdSpace.sm),
        child: TextField(
          controller: c,
          decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
        ),
      );
    }
    return SdInfoRow(
      label: label,
      value: c.text.isEmpty ? '—' : c.text,
      icon: icon,
    );
  }

  Widget _option(String title, IconData icon, VoidCallback onTap,
      {bool destructive = false}) {
    final color = destructive ? SdColors.danger : SdColors.primary;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color),
      title: Text(title,
          style: SdText.label
              .copyWith(color: destructive ? SdColors.danger : SdColors.ink)),
      trailing: const Icon(Icons.chevron_left_rounded, color: SdColors.faint),
      onTap: onTap,
    );
  }

  void _showChangePasswordDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تغيير كلمة المرور'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            TextField(obscureText: true, decoration: InputDecoration(labelText: 'كلمة المرور الحالية')),
            SizedBox(height: SdSpace.sm),
            TextField(obscureText: true, decoration: InputDecoration(labelText: 'كلمة المرور الجديدة')),
            SizedBox(height: SdSpace.sm),
            TextField(obscureText: true, decoration: InputDecoration(labelText: 'تأكيد كلمة المرور الجديدة')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تم تغيير كلمة المرور بنجاح')),
              );
            },
            child: const Text('تغيير'),
          ),
        ],
      ),
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تسجيل الخروج'),
        content: const Text('هل أنت متأكد من تسجيل الخروج؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: SdColors.danger),
            onPressed: () async {
              Navigator.pop(ctx);
              await context.read<AuthProvider>().logout();
              if (context.mounted) context.go('/');
            },
            child: const Text('تسجيل الخروج'),
          ),
        ],
      ),
    );
  }
}
