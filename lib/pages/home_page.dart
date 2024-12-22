import 'package:flutter/material.dart';
import 'google_drive_files_page.dart';
import 'statistics_page.dart';
import 'analysis_page.dart';
import 'users_page.dart';
import 'attendance_page.dart'; // استيراد صفحة الحضور

class HomePage extends StatelessWidget {
  final String permissions; // صلاحيات المستخدم
  final String username; // اسم المستخدم
  final String department; // القسم
  final String center; // المركز

  const HomePage({
    super.key,
    required this.permissions,
    required this.username,
    required this.department,
    required this.center,
  });

  void _showPermissionDenied(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('صلاحية غير كافية'),
        content: const Text(
          'ليس لديك صلاحية الوصول إلى هذه الصفحة.\nيرجى الاتصال على 07727787789 المسؤول.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('حسنًا'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'مرحبًا بك، $username',
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.blue[800],
      ),
      body: _buildContent(context),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue[800]!, Colors.blue[400]!],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Center(
                child: Text(
                  'القائمة الجانبية',
                  style: const TextStyle(
                    fontSize: 24,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            _buildDrawerTile(
              context,
              icon: Icons.people,
              label: 'المستخدمين',
              onTap: () {
                if (permissions == 'مدير') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => UsersPage(permissions: permissions),
                    ),
                  );
                } else {
                  _showPermissionDenied(context);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          const SizedBox(height: 20),
          _buildCenteredImage(),
          const SizedBox(height: 30),
          _buildButtonsGrid(context),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.blue[100],
        borderRadius: BorderRadius.circular(15),
      ),
      child: Text(
        'شركة رمز الصدارة / مرحبًا بك في تطبيق الزونات!\nالقسم: $department - المركز: $center',
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Colors.black,
        ),
      ),
    );
  }

  Widget _buildCenteredImage() {
    return Center(
      child: Container(
        width: 200,
        height: 200,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.5),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Image.asset(
            'assets/1.jpg',
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }

  Widget _buildButtonsGrid(BuildContext context) {
    return Wrap(
      spacing: 15.0,
      runSpacing: 15.0,
      alignment: WrapAlignment.center,
      children: [
        _buildButton(
          context,
          icon: Icons.map,
          label: 'خرائط الزونات',
          onPressed: () {
            if (permissions == 'مدير' ||
                permissions == 'ليدر' ||
                permissions == 'فني') {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const GoogleDriveFilesPage(),
                ),
              );
            } else {
              _showPermissionDenied(context);
            }
          },
        ),
        _buildButton(
          context,
          icon: Icons.bar_chart,
          label: 'إحصائيات الزونات',
          onPressed: () {
            if (permissions == 'مدير' || permissions == 'ليدر') {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const StatisticsPage(),
                ),
              );
            } else {
              _showPermissionDenied(context);
            }
          },
        ),
        _buildButton(
          context,
          icon: Icons.analytics,
          label: 'تحليل المعلومات',
          onPressed: () {
            if (permissions == 'مدير' || permissions == 'ليدر') {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AnalysisPage(),
                ),
              );
            } else {
              _showPermissionDenied(context);
            }
          },
        ),
        _buildButton(
          context,
          icon: Icons.fingerprint,
          label: 'بصمة الحضور',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => AttendancePage(
                  username: username,
                  center: center,
                  permissions: permissions, // تمرير صلاحيات المستخدم
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildDrawerTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.blue[800], size: 30),
      title: Text(
        label,
        style: const TextStyle(
          color: Colors.black,
          fontSize: 18,
        ),
      ),
      onTap: onTap,
    );
  }

  Widget _buildButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton.icon(
      icon: Icon(icon, color: Colors.white, size: 24),
      label: Text(
        label,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
        backgroundColor: Colors.blue[700],
      ),
    );
  }
}
