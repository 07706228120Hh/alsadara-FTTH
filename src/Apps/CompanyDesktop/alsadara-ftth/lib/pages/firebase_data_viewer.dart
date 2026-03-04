/// صفحة عرض بيانات Firebase مباشرة
/// للتحقق من البيانات المخزنة في Firestore
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firebase_availability.dart';

class FirebaseDataViewer extends StatefulWidget {
  const FirebaseDataViewer({super.key});

  @override
  State<FirebaseDataViewer> createState() => _FirebaseDataViewerState();
}

class _FirebaseDataViewerState extends State<FirebaseDataViewer> {
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  bool _isLoading = false;
  List<Map<String, dynamic>> _tenants = [];
  Map<String, List<Map<String, dynamic>>> _users = {};
  List<Map<String, dynamic>> _superAdmins = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!FirebaseAvailability.isAvailable) return;
    setState(() => _isLoading = true);

    try {
      // جلب Super Admins
      final superAdminDocs = await _firestore.collection('super_admins').get();
      _superAdmins = superAdminDocs.docs.map((doc) {
        return {'id': doc.id, ...doc.data()};
      }).toList();

      print('✅ Super Admins: ${_superAdmins.length}');

      // جلب Tenants
      final tenantDocs = await _firestore.collection('tenants').get();
      _tenants = tenantDocs.docs.map((doc) {
        return {'id': doc.id, ...doc.data()};
      }).toList();

      print('✅ Tenants: ${_tenants.length}');

      // جلب Users لكل Tenant
      for (var tenant in _tenants) {
        final userDocs = await _firestore
            .collection('tenants')
            .doc(tenant['id'])
            .collection('users')
            .get();

        _users[tenant['id']] = userDocs.docs.map((doc) {
          return {'id': doc.id, ...doc.data()};
        }).toList();

        print(
            '  └─ Users in ${tenant['name']}: ${_users[tenant['id']]?.length ?? 0}');
      }
    } catch (e) {
      print('❌ خطأ في جلب البيانات: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('عرض بيانات Firebase', style: GoogleFonts.cairo()),
        backgroundColor: const Color(0xFF1E3A8A),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'تحديث',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Super Admins Section
                  _buildSection(
                    title: 'Super Admins (${_superAdmins.length})',
                    icon: Icons.admin_panel_settings,
                    color: Colors.purple,
                    children: _superAdmins.map((admin) {
                      return _buildCard(
                        title: admin['username'] ?? 'N/A',
                        subtitle: admin['name'] ?? 'N/A',
                        data: admin,
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),

                  // Tenants Section
                  _buildSection(
                    title: 'Tenants (${_tenants.length})',
                    icon: Icons.business,
                    color: Colors.blue,
                    children: _tenants.map((tenant) {
                      final tenantUsers = _users[tenant['id']] ?? [];
                      return Column(
                        children: [
                          _buildCard(
                            title: tenant['code'] ?? 'N/A',
                            subtitle: tenant['name'] ?? 'N/A',
                            data: tenant,
                            trailing: Chip(
                              label: Text(
                                '${tenantUsers.length} مستخدم',
                                style: GoogleFonts.cairo(fontSize: 12),
                              ),
                              backgroundColor: Colors.blue[100],
                            ),
                          ),
                          // Users under this tenant
                          if (tenantUsers.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(left: 32, top: 8),
                              child: Column(
                                children: tenantUsers.map((user) {
                                  return _buildCard(
                                    title: user['username'] ?? 'N/A',
                                    subtitle: user['fullName'] ??
                                        user['name'] ??
                                        'N/A',
                                    data: user,
                                    isNested: true,
                                  );
                                }).toList(),
                              ),
                            ),
                        ],
                      );
                    }).toList(),
                  ),

                  // ملاحظة مهمة
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.amber[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber[200]!),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.amber[900]),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'تأكد من أن كود الشركة (code) في Firebase يطابق ما تدخله في صفحة تسجيل الدخول. البحث حساس لحالة الأحرف (Case Sensitive).',
                            style: GoogleFonts.cairo(
                              fontSize: 13,
                              color: Colors.amber[900],
                            ),
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

  Widget _buildSection({
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 8),
            Text(
              title,
              style: GoogleFonts.cairo(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...children,
      ],
    );
  }

  Widget _buildCard({
    required String title,
    required String subtitle,
    required Map<String, dynamic> data,
    Widget? trailing,
    bool isNested = false,
  }) {
    return Card(
      margin: EdgeInsets.only(bottom: 8, left: isNested ? 16 : 0),
      elevation: isNested ? 1 : 2,
      child: ExpansionTile(
        leading: Icon(
          isNested ? Icons.person : Icons.account_circle,
          color: isNested ? Colors.grey[600] : const Color(0xFF1E3A8A),
        ),
        title: Text(
          title,
          style: GoogleFonts.cairo(
            fontWeight: FontWeight.bold,
            fontSize: isNested ? 14 : 16,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: GoogleFonts.cairo(fontSize: isNested ? 12 : 14),
        ),
        trailing: trailing,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.grey[50],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: data.entries.map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: RichText(
                    text: TextSpan(
                      style: GoogleFonts.cairo(
                        fontSize: 12,
                        color: Colors.black87,
                      ),
                      children: [
                        TextSpan(
                          text: '${entry.key}: ',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        TextSpan(
                          text: _formatValue(entry.value),
                          style: TextStyle(color: Colors.grey[800]),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  String _formatValue(dynamic value) {
    if (value == null) return 'null';
    if (value is Timestamp) {
      return value.toDate().toString();
    }
    if (value is Map) {
      return 'Map(${value.length} items)';
    }
    if (value is List) {
      return 'List(${value.length} items)';
    }
    return value.toString();
  }
}
