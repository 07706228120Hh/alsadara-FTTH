/// اسم الصفحة: الصلاحيات
/// وصف الصفحة: صفحة إدارة صلاحيات المستخدمين
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'package:flutter/material.dart';
import '../../permissions/permissions.dart';

class PermissionsPage extends StatefulWidget {
  final Map<String, bool> userPermissions;
  final Map<String, bool> defaultPermissions;

  const PermissionsPage({
    super.key,
    required this.userPermissions,
    required this.defaultPermissions,
  });

  @override
  State<PermissionsPage> createState() => _PermissionsPageState();
}

class _PermissionsPageState extends State<PermissionsPage> {
  late Map<String, bool> tempPermissions;
  bool isLoading = false;
  final TextEditingController _defaultPasswordController =
      TextEditingController();
  bool _savingPassword = false;
  String? _loadedPassword; // للاحتفاظ بالقيمة المحملة
  bool _passwordObscured = true; // حالة إخفاء/إظهار كلمة المرور

  @override
  void initState() {
    super.initState();
    // دمج الصلاحيات الافتراضية مع صلاحيات المستخدم
    // لضمان ظهور جميع الصلاحيات حتى الجديدة التي لم يتم حفظها بعد
    tempPermissions = <String, bool>{};
    for (final key in widget.defaultPermissions.keys) {
      tempPermissions[key] = widget.userPermissions[key] ??
          widget.defaultPermissions[key] ??
          false;
    }
    _loadDefaultPassword();
  }

  Future<void> _loadDefaultPassword() async {
    final pwd = await PermissionService.getSecondSystemDefaultPassword();
    if (mounted) {
      setState(() {
        _loadedPassword = pwd;
        _defaultPasswordController.text = pwd ?? '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Responsive tweaks for mobile vs desktop/tablet
    final screenWidth = MediaQuery.of(context).size.width;
    int crossAxisCount;
    double childAspectRatio;

    if (screenWidth < 340) {
      crossAxisCount = 1; // very small phones
      childAspectRatio = 4.2;
    } else if (screenWidth < 380) {
      crossAxisCount = 1; // small phones
      childAspectRatio = 4.6;
    } else if (screenWidth < 600) {
      crossAxisCount = 2; // regular phones
      childAspectRatio = 3.2;
    } else if (screenWidth < 900) {
      crossAxisCount = 3; // small tablets
      childAspectRatio = 4.8;
    } else {
      crossAxisCount = 4; // desktop/wide
      childAspectRatio = 5.8;
    }

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 50,
        iconTheme: const IconThemeData(size: 20, color: Colors.white),
        title: const Text(
          'إدارة الصلاحيات',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.white,
            fontSize: 16,
          ),
        ),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: Column(
        children: [
          // حقل كلمة المرور الافتراضية أعلى الصفحة
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _defaultPasswordController,
                    obscureText: _passwordObscured,
                    decoration: InputDecoration(
                      labelText: 'كلمة المرور الافتراضية',
                      hintText: 'أدخل كلمة المرور الافتراضية (اختياري)',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      isDense: true,
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // زر الإظهار/الإخفاء
                          IconButton(
                            tooltip: _passwordObscured ? 'إظهار' : 'إخفاء',
                            icon: Icon(
                              _passwordObscured
                                  ? Icons.visibility_rounded
                                  : Icons.visibility_off_rounded,
                            ),
                            onPressed: () {
                              setState(() {
                                _passwordObscured = !_passwordObscured;
                              });
                            },
                          ),
                          if (_defaultPasswordController.text.isNotEmpty)
                            IconButton(
                              tooltip: 'مسح',
                              icon: const Icon(Icons.clear_rounded),
                              onPressed: () {
                                setState(() {
                                  _defaultPasswordController.clear();
                                });
                              },
                            ),
                        ],
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _savingPassword ? null : _saveDefaultPassword,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A237E),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: _savingPassword
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white)),
                          )
                        : const Icon(Icons.save),
                    label: Text(_savingPassword ? '...' : 'حفظ'),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                _loadedPassword == null || _loadedPassword!.isEmpty
                    ? 'لا توجد كلمة مرور افتراضية محفوظة حالياً'
                    : 'تم حفظ كلمة مرور افتراضية',
                style: TextStyle(
                  fontSize: 11,
                  color: (_loadedPassword == null || _loadedPassword!.isEmpty)
                      ? Colors.red[700]
                      : Colors.green[700],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          // قائمة الصلاحيات في عامودين
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 6,
                mainAxisSpacing: 6,
                childAspectRatio: childAspectRatio,
              ),
              itemCount: widget.defaultPermissions.keys.length,
              itemBuilder: (context, index) {
                final key = widget.defaultPermissions.keys.elementAt(index);
                return Card(
                  elevation: 2,
                  margin: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: tempPermissions[key]!
                            ? [Colors.green[100]!, Colors.green[200]!]
                            : [Colors.red[100]!, Colors.red[200]!],
                      ),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        setState(() {
                          tempPermissions[key] =
                              !(tempPermissions[key] ?? false);
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 52),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // الأيقونة
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: tempPermissions[key]!
                                      ? Colors.green[300]
                                      : Colors.red[300],
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Icon(
                                  _permissionIcon(key),
                                  color: tempPermissions[key]!
                                      ? Colors.green[900]
                                      : Colors.red[900],
                                  size: screenWidth < 600 ? 16 : 18,
                                ),
                              ),
                              const SizedBox(width: 8),
                              // العنوان
                              Expanded(
                                child: Text(
                                  _permissionTitle(key),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: screenWidth < 380
                                        ? 12
                                        : (screenWidth < 600 ? 14 : 16),
                                    color: tempPermissions[key]!
                                        ? Colors.green[900]
                                        : Colors.red[900],
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              // السويتش
                              Transform.scale(
                                scale: screenWidth < 380
                                    ? 0.95
                                    : (screenWidth < 600 ? 1.0 : 1.1),
                                child: Switch.adaptive(
                                  value: tempPermissions[key] ?? false,
                                  onChanged: (value) {
                                    setState(() {
                                      tempPermissions[key] = value;
                                    });
                                  },
                                  activeColor: Colors.green[700],
                                  activeTrackColor: Colors.green[300],
                                  inactiveThumbColor: Colors.red[700],
                                  inactiveTrackColor: Colors.red[300],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),

      // شريط الأزرار السفلي
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withValues(alpha: 0.2),
              blurRadius: 4,
              offset: const Offset(0, -1),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.cancel_outlined, size: 18),
                label: const Text('إلغاء', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                  side:
                      BorderSide(color: const Color.fromARGB(255, 172, 62, 62)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: isLoading ? null : _savePermissions,
                icon: isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.save_outlined, size: 16),
                label: Text(
                  isLoading ? 'جاري الحفظ...' : 'حفظ التغييرات',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color.fromARGB(255, 24, 167, 60),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveDefaultPassword() async {
    setState(() => _savingPassword = true);
    try {
      await PermissionService.saveSecondSystemDefaultPassword(
          _defaultPasswordController.text);
      if (mounted) {
        setState(() {
          _loadedPassword = _defaultPasswordController.text.trim().isEmpty
              ? null
              : _defaultPasswordController.text.trim();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _loadedPassword == null
                  ? 'تم حذف كلمة المرور الافتراضية'
                  : 'تم حفظ كلمة المرور الافتراضية',
            ),
            backgroundColor:
                _loadedPassword == null ? Colors.orange : Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في حفظ كلمة المرور: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _savingPassword = false);
    }
  }

  Future<void> _savePermissions() async {
    setState(() {
      isLoading = true;
    });

    try {
      await _saveAllPermissions(tempPermissions);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'تم حفظ الصلاحيات بشكل دائم وتطبيقها على جميع المستخدمين',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );

        // العودة للصفحة السابقة مع النتيجة
        Navigator.pop(context, tempPermissions);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في حفظ الصلاحيات: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> _saveAllPermissions(Map<String, bool> permissions) async {
    try {
      // V2: تحويل Map<String,bool> إلى Map<String,Map<String,bool>> وحفظها
      final v2Perms = <String, Map<String, bool>>{};
      for (final entry in permissions.entries) {
        v2Perms[entry.key] = {
          for (final action in PermissionService.availableActions)
            action: action == 'view' ? entry.value : false,
        };
      }
      await PermissionService.saveSecondSystemPermissionsV2(v2Perms);
    } catch (e) {
      throw Exception('فشل في حفظ الصلاحيات: $e');
    }
  }

  String _permissionTitle(String key) {
    switch (key) {
      case 'users':
        return 'إدارة المستخدمين';
      case 'subscriptions':
        return 'إدارة الاشتراكات';
      case 'tasks':
        return 'إدارة المهام';
      case 'zones':
        return 'إدارة الزونات';
      case 'accounts':
        return 'إدارة الحسابات';
      case 'account_records':
        return 'سجلات الحسابات';
      case 'export':
        return 'تصدير البيانات';
      case 'agents':
        return 'إدارة الوكلاء';
      case 'google_sheets':
        return 'حفظ في الخادم';
      case 'whatsapp':
        return 'رسائل WhatsApp';
      case 'wallet_balance':
        return 'رصيد المحفظة';
      case 'quick_search':
        return 'البحث السريع';
      case 'expiring_soon':
        return 'الانتهاء قريباً';
      case 'transactions':
        return 'التحويلات';
      case 'notifications':
        return 'الإشعارات';
      case 'audit_logs':
        return 'سجل التدقيق';
      case 'local_storage':
        return 'التخزين المحلي';
      case 'local_storage_import':
        return 'استيراد التخزين المحلي';
      case 'whatsapp_templates':
        return 'قوالب الرسائل';
      default:
        return key;
    }
  }

  IconData _permissionIcon(String key) {
    switch (key) {
      case 'users':
        return Icons.people;
      case 'subscriptions':
        return Icons.subscriptions;
      case 'tasks':
        return Icons.task;
      case 'zones':
        return Icons.location_on;
      case 'accounts':
        return Icons.account_balance;
      case 'account_records':
        return Icons.table_chart_rounded;
      case 'export':
        return Icons.file_download;
      case 'agents':
        return Icons.support_agent;
      case 'google_sheets':
        return Icons.table_chart;
      case 'whatsapp':
        return Icons.message;
      case 'wallet_balance':
        return Icons.account_balance_wallet;
      case 'quick_search':
        return Icons.search_rounded;
      case 'expiring_soon':
        return Icons.schedule_rounded;
      case 'transactions':
        return Icons.swap_horiz_rounded;
      case 'notifications':
        return Icons.notifications_rounded;
      case 'audit_logs':
        return Icons.history_rounded;
      case 'local_storage':
        return Icons.storage_rounded;
      case 'local_storage_import':
        return Icons.cloud_download_rounded;
      case 'whatsapp_templates':
        return Icons.description_rounded;
      default:
        return Icons.settings;
    }
  }
}
