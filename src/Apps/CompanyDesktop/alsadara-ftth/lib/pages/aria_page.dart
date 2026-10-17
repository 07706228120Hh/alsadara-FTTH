/// اسم الصفحة: صفحة أريا
/// وصف الصفحة: صفحة أريا للخدمات الخاصة والمتقدمة
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'package:flutter/material.dart';
import '../frontend/frontend.dart'; // نظام تصميم الصدارة الموحّد (sd)
import 'google_drive_files_page.dart';
import 'statistics_page.dart';
import 'analysis_page.dart';

class AriaPage extends StatelessWidget {
  final String permissions;
  final String username;
  final String department;
  final String center;

  const AriaPage({
    super.key,
    required this.permissions,
    required this.username,
    required this.department,
    required this.center,
  });

  void _showUserDetails(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: const Text('تفاصيل المستخدم',
              style: TextStyle(
                  fontFamily: SdText.family,
                  color: SdColors.primary,
                  fontWeight: FontWeight.w900),
              textAlign: TextAlign.center),
          content: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: SdColors.surfaceAlt,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildUserDetailRow(Icons.person, 'اسم المستخدم', username),
                const SizedBox(height: 10),
                _buildUserDetailRow(Icons.business, 'القسم', department),
                const SizedBox(height: 10),
                _buildUserDetailRow(Icons.location_on, 'المركز', center),
                const SizedBox(height: 10),
                _buildUserDetailRow(Icons.security, 'الصلاحية', permissions),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق',
                  style: TextStyle(
                      fontFamily: SdText.family,
                      fontSize: 16,
                      color: SdColors.primary)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: SdColors.primaryLight, size: 20),
        const SizedBox(width: 8),
        Text('$label: ', style: SdText.label),
        Expanded(child: Text(value, style: SdText.bodySm)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SdTheme.scope(
      child: Scaffold(
        backgroundColor: SdColors.ground,
        appBar: SdAppBar(
          title: 'مرحباً بك $username',
          subtitle: 'لوحة التحكم الرئيسية',
          actions: [
            SdAppBarAction(
              icon: Icons.account_circle,
              label: 'تفاصيل المستخدم',
              onPressed: () => _showUserDetails(context),
            ),
          ],
        ),
        body: _buildContent(context),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SdSectionHeader(title: 'الأقسام المتاحة'),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  SdMenuTile(
                    icon: Icons.analytics,
                    title: 'تحليل البيانات',
                    group: SdGroup.platform,
                    layout: SdTileLayout.horizontal,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AnalysisPage(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  SdMenuTile(
                    icon: Icons.bar_chart,
                    title: 'الزونات',
                    group: SdGroup.field,
                    layout: SdTileLayout.horizontal,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const StatisticsPage(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  SdMenuTile(
                    icon: Icons.folder_shared,
                    title: 'خرائط الزونات',
                    group: SdGroup.field,
                    layout: SdTileLayout.horizontal,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const GoogleDriveFilesPage(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
