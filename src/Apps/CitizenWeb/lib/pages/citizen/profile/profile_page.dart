import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../config/app_theme.dart';

/// صفحة الملف الشخصي
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _isEditing = false;

  // بيانات المستخدم (تجريبية)
  final Map<String, dynamic> _userData = {
    'name': 'أحمد محمد العلي',
    'phone': '0512345678',
    'email': 'ahmed@example.com',
    'nationalId': '1234567890',
    'address': 'الرياض، حي النخيل، شارع الملك فهد',
    'city': 'الرياض',
    'postalCode': '12345',
    'joinDate': '2024-01-15',
  };

  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _emailController;
  late TextEditingController _addressController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: _userData['name']);
    _phoneController = TextEditingController(text: _userData['phone']);
    _emailController = TextEditingController(text: _userData['email']);
    _addressController = TextEditingController(text: _userData['address']);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 900;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        appBar: AppBar(
          title: const Text('الملف الشخصي'),
          backgroundColor: AppTheme.primaryColor,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/citizen/home'),
          ),
          actions: [
            IconButton(
              icon: Icon(_isEditing ? Icons.close : Icons.edit),
              onPressed: () {
                setState(() {
                  if (_isEditing) {
                    // إلغاء التعديل
                    _nameController.text = _userData['name'];
                    _phoneController.text = _userData['phone'];
                    _emailController.text = _userData['email'];
                    _addressController.text = _userData['address'];
                  }
                  _isEditing = !_isEditing;
                });
              },
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: EdgeInsets.all(isWide ? 32 : 16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Column(
                children: [
                  // صورة الملف الشخصي
                  _buildProfileHeader(),
                  const SizedBox(height: 24),

                  // البيانات الشخصية
                  _buildInfoCard(
                    title: 'البيانات الشخصية',
                    icon: Icons.person,
                    children: [
                      _buildInfoRow(
                        'الاسم الكامل',
                        _userData['name'],
                        Icons.person_outline,
                        controller: _nameController,
                        editable: true,
                      ),
                      _buildInfoRow(
                        'رقم الهوية',
                        _userData['nationalId'],
                        Icons.badge_outlined,
                      ),
                      _buildInfoRow(
                        'تاريخ الانضمام',
                        _formatDate(_userData['joinDate']),
                        Icons.calendar_today_outlined,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // معلومات الاتصال
                  _buildInfoCard(
                    title: 'معلومات الاتصال',
                    icon: Icons.contact_phone,
                    children: [
                      _buildInfoRow(
                        'رقم الجوال',
                        _userData['phone'],
                        Icons.phone_outlined,
                        controller: _phoneController,
                        editable: true,
                      ),
                      _buildInfoRow(
                        'البريد الإلكتروني',
                        _userData['email'],
                        Icons.email_outlined,
                        controller: _emailController,
                        editable: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // العنوان
                  _buildInfoCard(
                    title: 'العنوان',
                    icon: Icons.location_on,
                    children: [
                      _buildInfoRow(
                        'العنوان التفصيلي',
                        _userData['address'],
                        Icons.home_outlined,
                        controller: _addressController,
                        editable: true,
                      ),
                      _buildInfoRow(
                        'المدينة',
                        _userData['city'],
                        Icons.location_city_outlined,
                      ),
                      _buildInfoRow(
                        'الرمز البريدي',
                        _userData['postalCode'],
                        Icons.markunread_mailbox_outlined,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // الإجراءات
                  _buildActionsCard(),
                  const SizedBox(height: 24),

                  // زر الحفظ
                  if (_isEditing) _buildSaveButton(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: AppTheme.primaryGradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.bottomLeft,
            children: [
              CircleAvatar(
                radius: 50,
                backgroundColor: Colors.white,
                child: Text(
                  _userData['name'].toString().substring(0, 2),
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ),
              if (_isEditing)
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: AppTheme.accentColor,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.camera_alt,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _userData['name'],
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _userData['phone'],
            style: TextStyle(
              fontSize: 16,
              color: Colors.white.withOpacity(0.9),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.verified, color: Colors.greenAccent, size: 18),
                SizedBox(width: 8),
                Text(
                  'حساب موثق',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(icon, color: AppTheme.primaryColor),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textDark,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    String label,
    String value,
    IconData icon, {
    TextEditingController? controller,
    bool editable = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.textGrey, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textGrey,
                  ),
                ),
                const SizedBox(height: 4),
                if (_isEditing && editable && controller != null)
                  TextField(
                    controller: controller,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  )
                else
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 16,
                      color: AppTheme.textDark,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionsCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        children: [
          _buildActionTile(
            'تغيير كلمة المرور',
            Icons.lock_outline,
            () => _showChangePasswordDialog(),
          ),
          const Divider(height: 1),
          _buildActionTile(
            'إعدادات الإشعارات',
            Icons.notifications_outlined,
            () => context.go('/citizen/notifications'),
          ),
          const Divider(height: 1),
          _buildActionTile('الخصوصية والأمان', Icons.security_outlined, () {}),
          const Divider(height: 1),
          _buildActionTile(
            'تسجيل الخروج',
            Icons.logout,
            () => _showLogoutDialog(),
            isDestructive: true,
          ),
        ],
      ),
    );
  }

  Widget _buildActionTile(
    String title,
    IconData icon,
    VoidCallback onTap, {
    bool isDestructive = false,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        color: isDestructive ? AppTheme.errorColor : AppTheme.primaryColor,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: isDestructive ? AppTheme.errorColor : AppTheme.textDark,
        ),
      ),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: onTap,
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _saveChanges,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.successColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: const Text(
          'حفظ التغييرات',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  void _saveChanges() {
    setState(() {
      _userData['name'] = _nameController.text;
      _userData['phone'] = _phoneController.text;
      _userData['email'] = _emailController.text;
      _userData['address'] = _addressController.text;
      _isEditing = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('تم حفظ التغييرات بنجاح'),
        backgroundColor: AppTheme.successColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _showChangePasswordDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تغيير كلمة المرور'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'كلمة المرور الحالية',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'كلمة المرور الجديدة',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'تأكيد كلمة المرور الجديدة',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
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
      builder: (context) => AlertDialog(
        title: const Text('تسجيل الخروج'),
        content: const Text('هل أنت متأكد من تسجيل الخروج؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              context.go('/');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorColor,
            ),
            child: const Text('تسجيل الخروج'),
          ),
        ],
      ),
    );
  }

  String _formatDate(String dateStr) {
    final date = DateTime.parse(dateStr);
    return '${date.day}/${date.month}/${date.year}';
  }
}
