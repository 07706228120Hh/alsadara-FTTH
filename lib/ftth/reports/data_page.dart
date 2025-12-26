/// اسم الصفحة: بيانات
/// وصف الصفحة: صفحة موحدة تجمع بين تفاصيل الوكلاء وبيانات المستخدمين
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'package:flutter/material.dart';
import 'agents_details_page.dart';
import '../users/users_data_page.dart';

class DataPage extends StatefulWidget {
  final String authToken;
  const DataPage({super.key, required this.authToken});

  @override
  State<DataPage> createState() => _DataPageState();
}

class _DataPageState extends State<DataPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF1A237E),
                Color(0xFF3949AB),
                Color(0xFF5C6BC0),
              ],
            ),
          ),
        ),
        title: const Text(
          'بيانات',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.normal,
            fontSize: 13,
          ),
          tabs: const [
            Tab(
              icon: Icon(Icons.info_outline_rounded),
              text: 'تفاصيل الوكلاء',
            ),
            Tab(
              icon: Icon(Icons.people_alt_rounded),
              text: 'بيانات المستخدمين',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // تفاصيل الوكلاء
          _AgentsDetailsContent(authToken: widget.authToken),
          // بيانات المستخدمين
          _UsersDataContent(authToken: widget.authToken),
        ],
      ),
    );
  }
}

/// محتوى تفاصيل الوكلاء (بدون AppBar)
class _AgentsDetailsContent extends StatelessWidget {
  final String authToken;
  const _AgentsDetailsContent({required this.authToken});

  @override
  Widget build(BuildContext context) {
    return AgentsDetailsPage(authToken: authToken);
  }
}

/// محتوى بيانات المستخدمين (بدون AppBar)
class _UsersDataContent extends StatelessWidget {
  final String authToken;
  const _UsersDataContent({required this.authToken});

  @override
  Widget build(BuildContext context) {
    return UsersDataPage(authToken: authToken);
  }
}
