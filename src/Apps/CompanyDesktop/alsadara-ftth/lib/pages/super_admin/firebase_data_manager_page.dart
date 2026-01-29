/// صفحة إدارة بيانات Firebase
/// تعرض جميع البيانات المخزنة في Firestore مع إمكانية التعديل والحذف
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'admin_theme.dart';

class FirebaseDataManagerPage extends StatefulWidget {
  const FirebaseDataManagerPage({super.key});

  @override
  State<FirebaseDataManagerPage> createState() =>
      _FirebaseDataManagerPageState();
}

class _FirebaseDataManagerPageState extends State<FirebaseDataManagerPage>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late TabController _tabController;

  String _searchQuery = '';
  bool _isLoading = false;

  // Collections الرئيسية في Firebase
  final List<String> _collections = [
    'super_admins',
    'tenants',
    'system_settings',
    'app_config',
  ];

  String _selectedCollection = 'tenants';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _collections.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _selectedCollection = _collections[_tabController.index];
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: AdminTheme.surfaceColor,
        elevation: 0,
        scrolledUnderElevation: 1,
        surfaceTintColor: Colors.transparent,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF9800), Color(0xFFFF5722)],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.storage, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            const Text(
              'إدارة بيانات Firebase',
              style: TextStyle(
                color: AdminTheme.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ],
        ),
        iconTheme: const IconThemeData(color: AdminTheme.textPrimary),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AdminTheme.borderColor),
              ),
            ),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              indicatorColor: AdminTheme.primaryColor,
              indicatorWeight: 3,
              labelColor: AdminTheme.primaryColor,
              unselectedLabelColor: AdminTheme.textMuted,
              labelStyle: const TextStyle(fontWeight: FontWeight.w600),
              tabs: _collections
                  .map((c) => Tab(
                        child: Row(
                          children: [
                            Icon(_getCollectionIcon(c), size: 18),
                            const SizedBox(width: 8),
                            Text(_getCollectionName(c)),
                          ],
                        ),
                      ))
                  .toList(),
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AdminTheme.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.refresh,
                  color: AdminTheme.primaryColor, size: 20),
            ),
            onPressed: () => setState(() {}),
            tooltip: 'تحديث',
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: ElevatedButton.icon(
              onPressed: () => _showAddDocumentDialog(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('إضافة جديد'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminTheme.accentColor,
                foregroundColor: Colors.white,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // شريط البحث
          Container(
            padding: const EdgeInsets.all(20),
            child: AdminTheme.buildSearchBar(
              hint: 'البحث في ${_getCollectionName(_selectedCollection)}...',
              onChanged: (value) =>
                  setState(() => _searchQuery = value.toLowerCase()),
            ),
          ),
          // المحتوى
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: _collections.map((collection) {
                return _buildCollectionView(collection);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getCollectionIcon(String collection) {
    switch (collection) {
      case 'super_admins':
        return Icons.admin_panel_settings;
      case 'tenants':
        return Icons.business;
      case 'system_settings':
        return Icons.settings;
      case 'app_config':
        return Icons.app_settings_alt;
      default:
        return Icons.folder;
    }
  }

  String _getCollectionName(String collection) {
    switch (collection) {
      case 'super_admins':
        return 'مديري النظام';
      case 'tenants':
        return 'الشركات';
      case 'system_settings':
        return 'إعدادات النظام';
      case 'app_config':
        return 'إعدادات التطبيق';
      default:
        return collection;
    }
  }

  // ترجمة أسماء الحقول للعربية
  String _getFieldLabel(String field) {
    final labels = {
      'username': 'اسم المستخدم',
      'password': 'كلمة المرور',
      'passwordHash': 'كلمة المرور (مشفرة)',
      'plainPassword': 'كلمة المرور',
      'name': 'الاسم',
      'fullName': 'الاسم الكامل',
      'email': 'البريد الإلكتروني',
      'phone': 'رقم الهاتف',
      'phoneNumber': 'رقم الهاتف',
      'address': 'العنوان',
      'city': 'المدينة',
      'code': 'كود الشركة',
      'role': 'الدور/الصلاحية',
      'isActive': 'الحالة (نشط)',
      'createdAt': 'تاريخ الإنشاء',
      'updatedAt': 'تاريخ التحديث',
      'key': 'المفتاح',
      'value': 'القيمة',
      'description': 'الوصف',
      'status': 'الحالة',
      'type': 'النوع',
    };
    return labels[field] ?? field;
  }

  // الحقول التي يجب إخفاؤها من التعديل
  bool _shouldHideField(String field) {
    return ['passwordHash', 'createdAt', 'updatedAt', 'id'].contains(field);
  }

  Widget _buildCollectionView(String collectionName) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection(collectionName).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return AdminTheme.buildLoadingIndicator(
              message: 'جاري تحميل البيانات...');
        }

        if (snapshot.hasError) {
          return AdminTheme.buildErrorWidget(
            message: 'حدث خطأ في تحميل البيانات',
            details: snapshot.error.toString(),
            onRetry: () => setState(() {}),
          );
        }

        final docs = snapshot.data?.docs ?? [];

        // تصفية حسب البحث
        final filteredDocs = docs.where((doc) {
          if (_searchQuery.isEmpty) return true;
          final data = doc.data() as Map<String, dynamic>;
          return data.toString().toLowerCase().contains(_searchQuery);
        }).toList();

        if (filteredDocs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AdminTheme.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: Icon(Icons.inbox_outlined,
                      size: 48, color: AdminTheme.primaryColor),
                ),
                const SizedBox(height: 20),
                Text(
                  _searchQuery.isEmpty ? 'لا توجد بيانات' : 'لا توجد نتائج',
                  style: const TextStyle(
                      color: AdminTheme.textSecondary,
                      fontSize: 18,
                      fontWeight: FontWeight.w500),
                ),
              ],
            ),
          );
        }

        // عرض خاص للشركات مع المستخدمين
        if (collectionName == 'tenants') {
          return _buildTenantsView(filteredDocs);
        }

        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: filteredDocs.length,
          itemBuilder: (context, index) {
            final doc = filteredDocs[index];
            return _buildDocumentCard(collectionName, doc);
          },
        );
      },
    );
  }

  Widget _buildTenantsView(List<QueryDocumentSnapshot> tenants) {
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: tenants.length,
      itemBuilder: (context, index) {
        final tenant = tenants[index];
        final data = tenant.data() as Map<String, dynamic>;

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: AdminTheme.surfaceColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: AdminTheme.cardShadow,
            border: Border.all(color: AdminTheme.borderColor),
          ),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF9800), Color(0xFFFF5722)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child:
                    const Icon(Icons.business, color: Colors.white, size: 22),
              ),
              title: Text(
                data['name'] ?? 'بدون اسم',
                style: const TextStyle(
                  color: AdminTheme.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'الكود: ${data['code'] ?? 'N/A'} | ID: ${tenant.id}',
                  style: const TextStyle(
                      color: AdminTheme.textMuted, fontSize: 12),
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // حالة الربط
                  if (data['isLinkedToCitizenPortal'] == true)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.teal.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.link, size: 14, color: Colors.tealAccent),
                          SizedBox(width: 4),
                          Text('مرتبطة',
                              style: TextStyle(
                                  color: Colors.tealAccent, fontSize: 10)),
                        ],
                      ),
                    ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.edit, color: Colors.blue),
                    onPressed: () => _showEditDocumentDialog('tenants', tenant),
                    tooltip: 'تعديل',
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () =>
                        _showDeleteConfirmDialog('tenants', tenant.id),
                    tooltip: 'حذف',
                  ),
                ],
              ),
              children: [
                // بيانات الشركة
                _buildDataSection('بيانات الشركة', data),
                const Divider(color: AdminTheme.borderColor),
                // مستخدمي الشركة
                _buildTenantUsersSection(tenant.id),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTenantUsersSection(String tenantId) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('tenants')
          .doc(tenantId)
          .collection('users')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }

        final users = snapshot.data?.docs ?? [];

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.people, color: Colors.blueAccent, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'مستخدمي الشركة (${users.length})',
                    style: const TextStyle(
                      color: Colors.blueAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.person_add,
                        color: Colors.green, size: 20),
                    onPressed: () => _showAddUserDialog(tenantId),
                    tooltip: 'إضافة مستخدم',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (users.isEmpty)
                Text(
                  'لا يوجد مستخدمين',
                  style: TextStyle(color: Colors.white.withOpacity(0.5)),
                )
              else
                ...users.map((user) {
                  final userData = user.data() as Map<String, dynamic>;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D1B2A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: _getRoleColor(userData['role']),
                          radius: 18,
                          child: Text(
                            (userData['fullName'] ?? 'U')[0].toUpperCase(),
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                userData['fullName'] ?? 'بدون اسم',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold),
                              ),
                              Text(
                                '@${userData['username'] ?? 'N/A'} | ${userData['role'] ?? 'employee'}',
                                style: TextStyle(
                                    color: Colors.white.withOpacity(0.6),
                                    fontSize: 12),
                              ),
                              // عرض كلمة المرور النصية إذا وجدت
                              if (userData['plainPassword'] != null)
                                Row(
                                  children: [
                                    const Icon(Icons.key,
                                        size: 12, color: Colors.amber),
                                    const SizedBox(width: 4),
                                    Text(
                                      'كلمة المرور: ${userData['plainPassword']}',
                                      style: const TextStyle(
                                          color: Colors.amber, fontSize: 11),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                        // حالة المستخدم
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: userData['isActive'] == true
                                ? Colors.green.withOpacity(0.2)
                                : Colors.red.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            userData['isActive'] == true ? 'نشط' : 'معطل',
                            style: TextStyle(
                              color: userData['isActive'] == true
                                  ? Colors.green
                                  : Colors.red,
                              fontSize: 10,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit,
                              color: Colors.blue, size: 18),
                          onPressed: () => _showEditUserDialog(tenantId, user),
                          tooltip: 'تعديل',
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete,
                              color: Colors.red, size: 18),
                          onPressed: () =>
                              _showDeleteUserConfirmDialog(tenantId, user.id),
                          tooltip: 'حذف',
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }

  Color _getRoleColor(String? role) {
    switch (role) {
      case 'admin':
        return Colors.purple;
      case 'manager':
        return Colors.blue;
      case 'technical_leader':
        return Colors.orange;
      case 'technician':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  Widget _buildDocumentCard(String collection, QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return Card(
      color: const Color(0xFF1B263B),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFFF9800).withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.description, color: Color(0xFFFF9800)),
        ),
        title: Text(
          data['name'] ?? data['username'] ?? doc.id,
          style:
              const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          'ID: ${doc.id}',
          style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.copy, color: Colors.white54),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: json.encode(data)));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم نسخ البيانات')),
                );
              },
              tooltip: 'نسخ JSON',
            ),
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.blue),
              onPressed: () => _showEditDocumentDialog(collection, doc),
              tooltip: 'تعديل',
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () => _showDeleteConfirmDialog(collection, doc.id),
              tooltip: 'حذف',
            ),
          ],
        ),
        children: [
          _buildDataSection('البيانات', data),
        ],
      ),
    );
  }

  Widget _buildDataSection(String title, Map<String, dynamic> data) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFFFF9800),
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          ...data.entries.map((entry) {
            String valueStr = _formatValue(entry.value);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 150,
                    child: Text(
                      entry.key,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      valueStr,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  String _formatValue(dynamic value) {
    if (value == null) return 'null';
    if (value is Timestamp) {
      return DateFormat('yyyy-MM-dd HH:mm').format(value.toDate());
    }
    if (value is Map || value is List) {
      return json.encode(value);
    }
    return value.toString();
  }

  // ================= Dialog Methods =================

  void _showAddDocumentDialog() {
    final formKey = GlobalKey<FormState>();
    final Map<String, TextEditingController> controllers = {};

    // حقول افتراضية حسب النوع
    List<String> fields = [];
    if (_selectedCollection == 'super_admins') {
      fields = ['username', 'plainPassword', 'name', 'email', 'phone'];
    } else if (_selectedCollection == 'tenants') {
      fields = ['name', 'code', 'email', 'phone', 'address'];
    } else {
      fields = ['key', 'value'];
    }

    for (var field in fields) {
      controllers[field] = TextEditingController();
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1B263B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.add_circle, color: Color(0xFFFF9800)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'إضافة إلى ${_getCollectionName(_selectedCollection)}',
                style: const TextStyle(color: Colors.white, fontSize: 18),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: fields.map((field) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: TextFormField(
                      controller: controllers[field],
                      style:
                          const TextStyle(color: Colors.black87, fontSize: 15),
                      obscureText: field.toLowerCase().contains('password'),
                      decoration: InputDecoration(
                        labelText: _getFieldLabel(field),
                        labelStyle: const TextStyle(
                          color: Colors.grey,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        floatingLabelStyle: const TextStyle(
                          color: Color(0xFFFF9800),
                          fontWeight: FontWeight.bold,
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              const BorderSide(color: Colors.grey, width: 1.5),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                              color: Color(0xFFFF9800), width: 2),
                        ),
                        prefixIcon: Icon(
                          _getFieldIcon(field),
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              final data = <String, dynamic>{};
              controllers.forEach((key, controller) {
                if (controller.text.isNotEmpty) {
                  data[key] = controller.text;
                  // إضافة passwordHash إذا كان plainPassword
                  if (key == 'plainPassword') {
                    data['passwordHash'] = _hashPassword(controller.text);
                  }
                }
              });
              data['createdAt'] = FieldValue.serverTimestamp();
              data['isActive'] = true;

              await _firestore.collection(_selectedCollection).add(data);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('✅ تمت الإضافة بنجاح')),
              );
            },
            icon: const Icon(Icons.add, size: 18),
            label: const Text('إضافة'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF9800),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  // أيقونة حسب نوع الحقل
  IconData _getFieldIcon(String field) {
    final icons = {
      'username': Icons.person,
      'password': Icons.lock,
      'plainPassword': Icons.lock,
      'passwordHash': Icons.lock,
      'name': Icons.badge,
      'fullName': Icons.badge,
      'email': Icons.email,
      'phone': Icons.phone,
      'phoneNumber': Icons.phone,
      'address': Icons.location_on,
      'city': Icons.location_city,
      'code': Icons.qr_code,
      'role': Icons.admin_panel_settings,
      'isActive': Icons.toggle_on,
      'key': Icons.key,
      'value': Icons.text_fields,
    };
    return icons[field] ?? Icons.text_fields;
  }

  void _showEditDocumentDialog(String collection, QueryDocumentSnapshot doc) {
    final data = Map<String, dynamic>.from(doc.data() as Map);
    final controllers = <String, TextEditingController>{};

    // فلترة الحقول - إظهار plainPassword بدلاً من passwordHash
    data.forEach((key, value) {
      if (value is! Timestamp && value is! Map && value is! List) {
        // تخطي passwordHash إذا كان plainPassword موجود
        if (key == 'passwordHash' && data.containsKey('plainPassword')) {
          return;
        }
        controllers[key] = TextEditingController(text: value?.toString() ?? '');
      }
    });

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1B263B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.edit, color: Colors.blue),
            const SizedBox(width: 8),
            const Text('تعديل المستند',
                style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: controllers.entries.map((entry) {
                final isReadOnly = [
                  'id',
                  'createdAt',
                  'updatedAt',
                  'passwordHash'
                ].contains(entry.key);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: TextField(
                    controller: entry.value,
                    readOnly: isReadOnly,
                    style: TextStyle(
                      color: isReadOnly ? Colors.grey : Colors.black87,
                      fontSize: 15,
                    ),
                    decoration: InputDecoration(
                      labelText: _getFieldLabel(entry.key),
                      labelStyle: const TextStyle(
                        color: Colors.grey,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      floatingLabelStyle: TextStyle(
                        color: isReadOnly ? Colors.grey : Colors.blue,
                        fontWeight: FontWeight.bold,
                      ),
                      filled: true,
                      fillColor:
                          isReadOnly ? Colors.grey.shade200 : Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color:
                              isReadOnly ? Colors.grey.shade400 : Colors.grey,
                          width: 1.5,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            const BorderSide(color: Colors.blue, width: 2),
                      ),
                      prefixIcon: Icon(
                        _getFieldIcon(entry.key),
                        color: isReadOnly ? Colors.grey : Colors.blue.shade300,
                      ),
                      suffixIcon: isReadOnly
                          ? const Icon(Icons.lock, color: Colors.grey, size: 18)
                          : null,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              final updates = <String, dynamic>{};
              controllers.forEach((key, controller) {
                if (!['id', 'createdAt', 'updatedAt', 'passwordHash']
                    .contains(key)) {
                  updates[key] = controller.text;
                  // تحديث passwordHash إذا تم تغيير plainPassword
                  if (key == 'plainPassword') {
                    updates['passwordHash'] = _hashPassword(controller.text);
                  }
                }
              });
              updates['updatedAt'] = FieldValue.serverTimestamp();

              await _firestore
                  .collection(collection)
                  .doc(doc.id)
                  .update(updates);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('✅ تم التحديث بنجاح')),
              );
            },
            icon: const Icon(Icons.save, size: 18),
            label: const Text('حفظ'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmDialog(String collection, String docId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1B263B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 8),
            Text('تأكيد الحذف', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Text(
          'هل أنت متأكد من حذف هذا المستند؟\nلا يمكن التراجع عن هذا الإجراء.',
          style: TextStyle(color: Colors.white.withOpacity(0.8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              // حذف المستخدمين الفرعيين إذا كان tenant
              if (collection == 'tenants') {
                final usersSnapshot = await _firestore
                    .collection('tenants')
                    .doc(docId)
                    .collection('users')
                    .get();
                for (var user in usersSnapshot.docs) {
                  await user.reference.delete();
                }
              }
              await _firestore.collection(collection).doc(docId).delete();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تم الحذف بنجاح')),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
  }

  void _showAddUserDialog(String tenantId) {
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    final fullNameController = TextEditingController();
    String selectedRole = 'employee';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1B263B),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.person_add, color: Colors.green, size: 28),
              SizedBox(width: 10),
              Text('إضافة مستخدم جديد',
                  style: TextStyle(color: Colors.white, fontSize: 18)),
            ],
          ),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildDialogTextField(
                    controller: fullNameController,
                    label: 'الاسم الكامل',
                    icon: Icons.badge,
                    color: Colors.green,
                  ),
                  const SizedBox(height: 16),
                  _buildDialogTextField(
                    controller: usernameController,
                    label: 'اسم المستخدم',
                    icon: Icons.person,
                    color: Colors.green,
                  ),
                  const SizedBox(height: 16),
                  _buildDialogTextField(
                    controller: passwordController,
                    label: 'كلمة المرور',
                    icon: Icons.lock,
                    color: Colors.green,
                    obscureText: true,
                  ),
                  const SizedBox(height: 16),
                  _buildDialogDropdown(
                    value: selectedRole,
                    label: 'الدور / الصلاحية',
                    icon: Icons.admin_panel_settings,
                    items: const [
                      DropdownMenuItem(
                          value: 'admin',
                          child: Text('مدير',
                              style: TextStyle(color: Colors.black87))),
                      DropdownMenuItem(
                          value: 'manager',
                          child: Text('مشرف',
                              style: TextStyle(color: Colors.black87))),
                      DropdownMenuItem(
                          value: 'employee',
                          child: Text('موظف',
                              style: TextStyle(color: Colors.black87))),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => selectedRole = value!),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                if (usernameController.text.isEmpty ||
                    passwordController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('⚠️ يرجى ملء جميع الحقول المطلوبة')),
                  );
                  return;
                }

                await _firestore
                    .collection('tenants')
                    .doc(tenantId)
                    .collection('users')
                    .add({
                  'username': usernameController.text,
                  'passwordHash': _hashPassword(passwordController.text),
                  'plainPassword': passwordController.text,
                  'fullName': fullNameController.text,
                  'role': selectedRole,
                  'isActive': true,
                  'createdAt': FieldValue.serverTimestamp(),
                });
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('✅ تمت إضافة المستخدم بنجاح')),
                );
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('إضافة'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // حقل نص موحد للنوافذ
  Widget _buildDialogTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    Color color = Colors.blue,
    bool obscureText = false,
    bool readOnly = false,
  }) {
    return TextField(
      controller: controller,
      readOnly: readOnly,
      obscureText: obscureText,
      style: TextStyle(
        color: readOnly ? Colors.grey : Colors.black87,
        fontSize: 15,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          color: Colors.grey,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        floatingLabelStyle: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
        ),
        filled: true,
        fillColor: readOnly ? Colors.grey.shade200 : Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
              color: readOnly ? Colors.grey.shade400 : Colors.grey, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: color, width: 2),
        ),
        prefixIcon: Icon(icon, color: color.withOpacity(0.7)),
      ),
    );
  }

  // قائمة منسدلة موحدة للنوافذ
  Widget _buildDialogDropdown({
    required String value,
    required String label,
    required IconData icon,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
    Color color = Colors.blue,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      dropdownColor: Colors.white,
      style: const TextStyle(color: Colors.black87, fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          color: Colors.grey,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        floatingLabelStyle: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.grey, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: color, width: 2),
        ),
        prefixIcon: Icon(icon, color: color.withOpacity(0.7)),
      ),
      items: items,
      onChanged: onChanged,
    );
  }

  void _showEditUserDialog(String tenantId, QueryDocumentSnapshot user) {
    final data = user.data() as Map<String, dynamic>;
    final usernameController = TextEditingController(text: data['username']);
    final fullNameController = TextEditingController(text: data['fullName']);
    final passwordController = TextEditingController();
    String selectedRole = data['role'] ?? 'employee';
    bool isActive = data['isActive'] ?? true;
    bool showPasswordField = false;

    // عرض كلمة المرور الحالية إذا كانت موجودة
    final currentPassword = data['plainPassword'] ?? '';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1B263B),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.edit, color: Colors.blue, size: 28),
              SizedBox(width: 10),
              Text('تعديل المستخدم',
                  style: TextStyle(color: Colors.white, fontSize: 18)),
            ],
          ),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildDialogTextField(
                    controller: fullNameController,
                    label: 'الاسم الكامل',
                    icon: Icons.badge,
                    color: Colors.blue,
                  ),
                  const SizedBox(height: 16),
                  _buildDialogTextField(
                    controller: usernameController,
                    label: 'اسم المستخدم',
                    icon: Icons.person,
                    color: Colors.blue,
                  ),
                  const SizedBox(height: 16),
                  _buildDialogDropdown(
                    value: selectedRole,
                    label: 'الدور / الصلاحية',
                    icon: Icons.admin_panel_settings,
                    color: Colors.blue,
                    items: const [
                      DropdownMenuItem(
                          value: 'admin',
                          child: Text('مدير',
                              style: TextStyle(color: Colors.black87))),
                      DropdownMenuItem(
                          value: 'manager',
                          child: Text('مشرف',
                              style: TextStyle(color: Colors.black87))),
                      DropdownMenuItem(
                          value: 'employee',
                          child: Text('موظف',
                              style: TextStyle(color: Colors.black87))),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => selectedRole = value!),
                  ),
                  const SizedBox(height: 16),
                  // عرض كلمة المرور الحالية
                  if (currentPassword.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade400),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.lock_outline,
                              color: Colors.grey, size: 20),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('كلمة المرور الحالية:',
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.grey)),
                              Text(currentPassword,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      color: Colors.black87,
                                      fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  // زر تغيير كلمة المرور
                  if (!showPasswordField)
                    OutlinedButton.icon(
                      onPressed: () =>
                          setDialogState(() => showPasswordField = true),
                      icon: const Icon(Icons.lock_reset, color: Colors.orange),
                      label: const Text('تغيير كلمة المرور',
                          style: TextStyle(color: Colors.orange)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.orange),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                      ),
                    ),
                  if (showPasswordField) ...[
                    _buildDialogTextField(
                      controller: passwordController,
                      label: 'كلمة المرور الجديدة',
                      icon: Icons.lock,
                      color: Colors.orange,
                      obscureText: true,
                    ),
                  ],
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade400),
                    ),
                    child: SwitchListTile(
                      title: const Text('الحساب نشط',
                          style:
                              TextStyle(color: Colors.black87, fontSize: 15)),
                      subtitle: Text(
                        isActive
                            ? 'المستخدم يمكنه تسجيل الدخول'
                            : 'المستخدم معطل',
                        style: TextStyle(
                            color: isActive ? Colors.green : Colors.red,
                            fontSize: 12),
                      ),
                      secondary: Icon(
                        isActive ? Icons.check_circle : Icons.cancel,
                        color: isActive ? Colors.green : Colors.red,
                      ),
                      value: isActive,
                      onChanged: (value) =>
                          setDialogState(() => isActive = value),
                      activeColor: Colors.green,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                final updateData = <String, dynamic>{
                  'username': usernameController.text,
                  'fullName': fullNameController.text,
                  'role': selectedRole,
                  'isActive': isActive,
                  'updatedAt': FieldValue.serverTimestamp(),
                };

                // إذا تم إدخال كلمة مرور جديدة
                if (passwordController.text.isNotEmpty) {
                  updateData['passwordHash'] =
                      _hashPassword(passwordController.text);
                  updateData['plainPassword'] = passwordController.text;
                }

                await _firestore
                    .collection('tenants')
                    .doc(tenantId)
                    .collection('users')
                    .doc(user.id)
                    .update(updateData);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('✅ تم تحديث المستخدم بنجاح')),
                );
              },
              icon: const Icon(Icons.save, size: 18),
              label: const Text('حفظ'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteUserConfirmDialog(String tenantId, String userId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1B263B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
            SizedBox(width: 10),
            Text('تأكيد حذف المستخدم',
                style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.red.withOpacity(0.3)),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.red),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'هل أنت متأكد من حذف هذا المستخدم؟\nهذا الإجراء لا يمكن التراجع عنه.',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              await _firestore
                  .collection('tenants')
                  .doc(tenantId)
                  .collection('users')
                  .doc(userId)
                  .delete();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('🗑️ تم حذف المستخدم بنجاح')),
              );
            },
            icon: const Icon(Icons.delete, size: 18),
            label: const Text('حذف'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  String _hashPassword(String password) {
    // Simple hash using SHA256
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}
