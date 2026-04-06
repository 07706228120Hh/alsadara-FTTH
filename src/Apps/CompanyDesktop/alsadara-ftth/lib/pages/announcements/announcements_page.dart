import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../services/announcement_service.dart';
import '../../services/api/api_client.dart';
import '../../services/api/api_config.dart';
import '../../services/vps_auth_service.dart';
import '../../services/departments_data_service.dart';
import '../../permissions/permission_manager.dart';

class AnnouncementsPage extends StatefulWidget {
  const AnnouncementsPage({super.key});

  @override
  State<AnnouncementsPage> createState() => _AnnouncementsPageState();
}

class _AnnouncementsPageState extends State<AnnouncementsPage> {
  static const _primaryColor = Color(0xFF1976D2);
  static const _dangerColor = Color(0xFFE53935);
  static const _successColor = Color(0xFF43A047);

  List<Map<String, dynamic>> _announcements = [];
  bool _isLoading = true;
  bool _hasError = false;

  bool get _canAdd => PermissionManager.instance.canAdd('announcements');
  bool get _canEdit => PermissionManager.instance.canEdit('announcements');
  bool get _canDelete => PermissionManager.instance.canDelete('announcements');

  bool get _isMobile => MediaQuery.of(context).size.width < 600;

  @override
  void initState() {
    super.initState();
    _loadAnnouncements();
  }

  Future<void> _loadAnnouncements() async {
    if (!mounted) return;
    setState(() { _isLoading = true; _hasError = false; });
    try {
      final response = await AnnouncementService.instance.getAllAnnouncements(pageSize: 100);
      if (mounted) {
        if (response['success'] == true) {
          setState(() {
            _announcements = List<Map<String, dynamic>>.from(response['data'] ?? []);
            _isLoading = false;
          });
        } else {
          setState(() { _hasError = true; _isLoading = false; });
        }
      }
    } catch (e) {
      if (mounted) setState(() { _hasError = true; _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = _isMobile;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        appBar: AppBar(
          title: Text(
            'الإعلانات والتبليغات',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: isMobile ? 16 : 20),
          ),
          backgroundColor: _primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            if (_canAdd)
              IconButton(icon: const Icon(Icons.add_circle_outline), tooltip: 'إعلان جديد', onPressed: () => _showCreateEditDialog()),
            IconButton(icon: const Icon(Icons.refresh), tooltip: 'تحديث', onPressed: _loadAnnouncements),
          ],
        ),
        body: _buildBody(),
        floatingActionButton: _canAdd
            ? FloatingActionButton(
                onPressed: () => _showCreateEditDialog(),
                backgroundColor: _primaryColor,
                foregroundColor: Colors.white,
                mini: isMobile,
                child: const Icon(Icons.add),
              )
            : null,
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: _isMobile ? 48 : 64, color: Colors.grey),
              const SizedBox(height: 12),
              const Text('حدث خطأ في تحميل الإعلانات', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton.icon(onPressed: _loadAnnouncements, icon: const Icon(Icons.refresh), label: const Text('إعادة المحاولة')),
            ],
          ),
        ),
      );
    }
    if (_announcements.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.campaign_outlined, size: _isMobile ? 56 : 80, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text('لا توجد إعلانات', style: TextStyle(fontSize: _isMobile ? 15 : 18, color: Colors.grey.shade600)),
              if (_canAdd) ...[
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () => _showCreateEditDialog(),
                  icon: const Icon(Icons.add),
                  label: const Text('إنشاء أول إعلان'),
                  style: ElevatedButton.styleFrom(backgroundColor: _primaryColor, foregroundColor: Colors.white),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAnnouncements,
      child: ListView.builder(
        padding: EdgeInsets.all(_isMobile ? 8 : 16),
        itemCount: _announcements.length,
        itemBuilder: (context, index) => _buildAnnouncementCard(_announcements[index]),
      ),
    );
  }

  Widget _buildAnnouncementCard(Map<String, dynamic> announcement) {
    final isMobile = _isMobile;
    final id = announcement['id'];
    final title = announcement['title'] ?? '';
    final body = announcement['body'] ?? '';
    final imageUrl = announcement['imageUrl'];
    final isPublished = announcement['isPublished'] == true;
    final createdAt = announcement['createdAt'] != null ? DateTime.tryParse(announcement['createdAt'].toString()) : null;
    final expiresAt = announcement['expiresAt'] != null ? DateTime.tryParse(announcement['expiresAt'].toString()) : null;
    final createdBy = announcement['createdBy'] ?? '';
    final readCount = announcement['readCount'] ?? 0;
    final targetType = announcement['targetType'] ?? 0;
    final targetValue = announcement['targetValue'] ?? '';
    final isUrgent = announcement['isUrgent'] == true;
    final isPinned = announcement['isPinned'] == true;
    final targetLabel = _getTargetLabel(targetType, targetValue, announcement);
    final isExpired = expiresAt != null && expiresAt.isBefore(DateTime.now());

    return Card(
      margin: EdgeInsets.only(bottom: isMobile ? 8 : 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(isMobile ? 10 : 12),
        side: BorderSide(color: isUrgent ? Colors.red : Colors.red.shade200, width: isUrgent ? 2 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 16, vertical: isMobile ? 8 : 12),
            decoration: BoxDecoration(
              color: isExpired ? Colors.grey.shade100 : isPublished ? _primaryColor.withOpacity(0.05) : Colors.orange.shade50,
              borderRadius: BorderRadius.vertical(top: Radius.circular(isMobile ? 10 : 12)),
            ),
            child: Row(
              children: [
                Icon(
                  isExpired ? Icons.schedule : isPublished ? Icons.campaign : Icons.visibility_off,
                  color: isExpired ? Colors.grey : isPublished ? _primaryColor : Colors.orange,
                  size: isMobile ? 18 : 20,
                ),
                SizedBox(width: isMobile ? 6 : 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: isMobile ? 13 : 16, color: isExpired ? Colors.grey : Colors.black87),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: isMobile ? 6 : 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isExpired ? Colors.grey.shade300 : isPublished ? _successColor.withOpacity(0.15) : Colors.orange.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    isExpired ? 'منتهي' : isPublished ? 'منشور' : 'مسودة',
                    style: TextStyle(fontSize: isMobile ? 10 : 11, fontWeight: FontWeight.bold, color: isExpired ? Colors.grey.shade700 : isPublished ? _successColor : Colors.orange),
                  ),
                ),
                if (isUrgent) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: isMobile ? 5 : 6, vertical: 2),
                    decoration: BoxDecoration(color: _dangerColor.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.warning_rounded, size: isMobile ? 10 : 12, color: _dangerColor),
                      const SizedBox(width: 2),
                      Text('عاجل', style: TextStyle(fontSize: isMobile ? 9 : 10, fontWeight: FontWeight.bold, color: _dangerColor)),
                    ]),
                  ),
                ],
                if (isPinned) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.push_pin_rounded, size: isMobile ? 14 : 16, color: _primaryColor),
                ],
                if (_canEdit || _canDelete) ...[
                  const SizedBox(width: 2),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert, size: isMobile ? 18 : 20),
                    padding: EdgeInsets.zero,
                    onSelected: (value) {
                      if (value == 'edit') _showCreateEditDialog(announcement: announcement);
                      if (value == 'delete') _confirmDelete(id);
                      if (value == 'report') _showReadReport(id);
                    },
                    itemBuilder: (context) => [
                      if (_canEdit) const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 18), SizedBox(width: 8), Text('تعديل')])),
                      if (_canEdit) const PopupMenuItem(value: 'report', child: Row(children: [Icon(Icons.analytics, size: 18, color: Colors.blue), SizedBox(width: 8), Text('تقرير القراءة', style: TextStyle(color: Colors.blue))])),
                      if (_canDelete) const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 18, color: Colors.red), SizedBox(width: 8), Text('حذف', style: TextStyle(color: Colors.red))])),
                    ],
                  ),
                ],
              ],
            ),
          ),
          // Image
          if (imageUrl != null && imageUrl.toString().isNotEmpty)
            Container(
              width: double.infinity,
              constraints: BoxConstraints(maxHeight: isMobile ? 150 : 200),
              child: Image.network(
                imageUrl.startsWith('http') ? imageUrl : '${ApiConfig.baseUrl.replaceFirst('/api', '')}$imageUrl',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          // Body
          Padding(
            padding: EdgeInsets.all(isMobile ? 10 : 16),
            child: Text(body, style: TextStyle(fontSize: isMobile ? 13 : 14, color: Colors.grey.shade800, height: 1.6)),
          ),
          // Footer
          Container(
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 16, vertical: isMobile ? 6 : 8),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.shade200))),
            child: Wrap(
              spacing: isMobile ? 8 : 16,
              runSpacing: 4,
              children: [
                _infoChip(Icons.person_outline, createdBy),
                if (createdAt != null) _infoChip(Icons.access_time, DateFormat('yyyy/MM/dd HH:mm').format(createdAt.toLocal())),
                _infoChip(Icons.visibility, '$readCount قراءة'),
                _infoChip(Icons.group_outlined, targetLabel),
                if (expiresAt != null) _infoChip(Icons.timer_off, 'ينتهي: ${DateFormat('yyyy/MM/dd').format(expiresAt.toLocal())}', color: isExpired ? _dangerColor : null),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoChip(IconData icon, String text, {Color? color}) {
    final isMobile = _isMobile;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: isMobile ? 12 : 14, color: color ?? Colors.grey.shade500),
        const SizedBox(width: 3),
        Flexible(child: Text(text, style: TextStyle(fontSize: isMobile ? 10 : 12, color: color ?? Colors.grey.shade600), overflow: TextOverflow.ellipsis)),
      ],
    );
  }

  String _getTargetLabel(int targetType, String targetValue, Map<String, dynamic> announcement) {
    switch (targetType) {
      case 0: return 'الكل';
      case 1: return 'قسم: $targetValue';
      case 2: return 'دور: $targetValue';
      case 3: return 'موقع: $targetValue';
      case 4:
        final targets = announcement['targetUsers'] as List?;
        return targets != null && targets.isNotEmpty ? 'مخصص (${targets.length} موظف)' : 'مخصص';
      default: return 'غير محدد';
    }
  }

  // ═══════════════════════════════════════
  // Create / Edit Dialog — responsive
  // ═══════════════════════════════════════

  Future<void> _showCreateEditDialog({Map<String, dynamic>? announcement}) async {
    final isEdit = announcement != null;
    final titleCtrl = TextEditingController(text: announcement?['title'] ?? '');
    final bodyCtrl = TextEditingController(text: announcement?['body'] ?? '');
    int targetType = announcement?['targetType'] ?? 0;
    String? targetValue = announcement?['targetValue'];
    bool isPublished = announcement?['isPublished'] ?? true;
    DateTime? expiresAt = announcement?['expiresAt'] != null ? DateTime.tryParse(announcement!['expiresAt'].toString()) : null;
    String? imageUrl = announcement?['imageUrl'];
    File? imageFile;
    bool isUrgent = announcement?['isUrgent'] ?? false;
    bool isPinned = announcement?['isPinned'] ?? false;
    List<Map<String, dynamic>> selectedUsers = [];
    bool isSaving = false;

    if (isEdit && targetType == 4) {
      final targets = announcement['targetUsers'] as List?;
      if (targets != null) selectedUsers = targets.map((t) => Map<String, dynamic>.from(t)).toList();
    }

    await DepartmentsDataService.instance.fetchDepartments();
    if (!mounted) return;

    final isMobile = _isMobile;

    await showDialog(
      context: context,
      barrierDismissible: false,
      useSafeArea: !isMobile,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final dialogContent = SingleChildScrollView(
              padding: EdgeInsets.all(isMobile ? 12 : 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // العنوان
                  TextField(
                    controller: titleCtrl,
                    style: TextStyle(fontSize: isMobile ? 14 : 16),
                    decoration: InputDecoration(
                      labelText: 'عنوان الإعلان *',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.title),
                      isDense: isMobile,
                      contentPadding: isMobile ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10) : null,
                    ),
                  ),
                  SizedBox(height: isMobile ? 10 : 16),

                  // المحتوى
                  TextField(
                    controller: bodyCtrl,
                    maxLines: isMobile ? 3 : 5,
                    style: TextStyle(fontSize: isMobile ? 14 : 16),
                    decoration: InputDecoration(
                      labelText: 'محتوى الإعلان *',
                      border: const OutlineInputBorder(),
                      alignLabelWithHint: true,
                      isDense: isMobile,
                      contentPadding: isMobile ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10) : null,
                    ),
                  ),
                  SizedBox(height: isMobile ? 10 : 16),

                  // الصورة
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1200);
                            if (picked != null) setDialogState(() => imageFile = File(picked.path));
                          },
                          icon: const Icon(Icons.image, size: 18),
                          label: Text(imageFile != null || imageUrl != null ? 'تغيير الصورة' : 'إضافة صورة', style: TextStyle(fontSize: isMobile ? 12 : 14)),
                        ),
                      ),
                      if (imageFile != null || imageUrl != null)
                        IconButton(icon: const Icon(Icons.close, color: Colors.red, size: 18), onPressed: () => setDialogState(() { imageFile = null; imageUrl = null; })),
                    ],
                  ),
                  if (imageFile != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.file(imageFile!, height: isMobile ? 80 : 120, width: double.infinity, fit: BoxFit.cover)),
                    ),
                  if (imageFile == null && imageUrl != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          imageUrl!.startsWith('http') ? imageUrl! : '${ApiConfig.baseUrl.replaceFirst('/api', '')}$imageUrl',
                          height: isMobile ? 80 : 120, width: double.infinity, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Text('تعذر تحميل الصورة'),
                        ),
                      ),
                    ),
                  SizedBox(height: isMobile ? 10 : 16),

                  // الاستهداف
                  Text('الاستهداف', style: TextStyle(fontWeight: FontWeight.bold, fontSize: isMobile ? 13 : 14)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    value: targetType,
                    isDense: true,
                    style: TextStyle(fontSize: isMobile ? 13 : 14, color: Colors.black87),
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.group, size: 20),
                      isDense: isMobile,
                      contentPadding: isMobile ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10) : null,
                    ),
                    items: [
                      DropdownMenuItem(value: 0, child: Text('الكل', style: TextStyle(fontSize: isMobile ? 13 : 14))),
                      DropdownMenuItem(value: 1, child: Text('حسب القسم', style: TextStyle(fontSize: isMobile ? 13 : 14))),
                      DropdownMenuItem(value: 2, child: Text('حسب الدور', style: TextStyle(fontSize: isMobile ? 13 : 14))),
                      DropdownMenuItem(value: 3, child: Text('حسب الموقع', style: TextStyle(fontSize: isMobile ? 13 : 14))),
                      DropdownMenuItem(value: 4, child: Text('مخصص', style: TextStyle(fontSize: isMobile ? 13 : 14))),
                    ],
                    onChanged: (v) => setDialogState(() { targetType = v ?? 0; targetValue = null; selectedUsers = []; }),
                  ),
                  const SizedBox(height: 10),

                  if (targetType == 1)
                    DropdownButtonFormField<String>(
                      value: targetValue,
                      isDense: true,
                      decoration: InputDecoration(labelText: 'اختر القسم', border: const OutlineInputBorder(), isDense: isMobile),
                      items: DepartmentsDataService.instance.departmentNames.map((d) => DropdownMenuItem(value: d, child: Text(d, style: TextStyle(fontSize: isMobile ? 13 : 14)))).toList(),
                      onChanged: (v) => setDialogState(() => targetValue = v),
                    ),

                  if (targetType == 2)
                    DropdownButtonFormField<String>(
                      value: targetValue,
                      isDense: true,
                      decoration: InputDecoration(labelText: 'اختر الدور', border: const OutlineInputBorder(), isDense: isMobile),
                      items: [
                        DropdownMenuItem(value: 'Employee', child: Text('موظف', style: TextStyle(fontSize: isMobile ? 13 : 14))),
                        DropdownMenuItem(value: 'CompanyAdmin', child: Text('مدير شركة', style: TextStyle(fontSize: isMobile ? 13 : 14))),
                        DropdownMenuItem(value: 'Manager', child: Text('مدير', style: TextStyle(fontSize: isMobile ? 13 : 14))),
                        DropdownMenuItem(value: 'Technician', child: Text('فني', style: TextStyle(fontSize: isMobile ? 13 : 14))),
                        DropdownMenuItem(value: 'Accountant', child: Text('محاسب', style: TextStyle(fontSize: isMobile ? 13 : 14))),
                      ],
                      onChanged: (v) => setDialogState(() => targetValue = v),
                    ),

                  if (targetType == 3)
                    TextField(
                      decoration: InputDecoration(labelText: 'اسم المركز/الموقع', border: const OutlineInputBorder(), isDense: isMobile),
                      onChanged: (v) => targetValue = v,
                      controller: TextEditingController(text: targetValue),
                      style: TextStyle(fontSize: isMobile ? 13 : 14),
                    ),

                  if (targetType == 4)
                    _buildCustomUserPicker(selectedUsers, setDialogState),

                  SizedBox(height: isMobile ? 10 : 16),

                  // تاريخ الانتهاء
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: expiresAt ?? DateTime.now().add(const Duration(days: 7)),
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(const Duration(days: 365)),
                            );
                            if (picked != null) setDialogState(() => expiresAt = picked);
                          },
                          icon: const Icon(Icons.calendar_today, size: 16),
                          label: Text(
                            expiresAt != null ? 'ينتهي: ${DateFormat('yyyy/MM/dd').format(expiresAt!)}' : 'تاريخ انتهاء',
                            style: TextStyle(fontSize: isMobile ? 12 : 14),
                          ),
                        ),
                      ),
                      if (expiresAt != null) IconButton(icon: const Icon(Icons.close, size: 16, color: Colors.red), onPressed: () => setDialogState(() => expiresAt = null)),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // النشر
                  SwitchListTile(
                    title: Text('نشر فوراً', style: TextStyle(fontSize: isMobile ? 13 : 14)),
                    subtitle: Text(isPublished ? 'سيظهر للموظفين مباشرة' : 'سيُحفظ كمسودة', style: TextStyle(fontSize: isMobile ? 11 : 12)),
                    value: isPublished,
                    onChanged: (v) => setDialogState(() => isPublished = v),
                    activeColor: _primaryColor,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                  // عاجل
                  SwitchListTile(
                    title: Text('عاجل', style: TextStyle(fontSize: isMobile ? 13 : 14, color: isUrgent ? _dangerColor : null)),
                    subtitle: Text(isUrgent ? 'يتطلب تأكيد "قرأت وفهمت"' : 'إعلان عادي', style: TextStyle(fontSize: isMobile ? 11 : 12)),
                    value: isUrgent,
                    onChanged: (v) => setDialogState(() => isUrgent = v),
                    activeColor: _dangerColor,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    secondary: Icon(Icons.warning_rounded, size: 20, color: isUrgent ? _dangerColor : Colors.grey.shade400),
                  ),
                  // تثبيت
                  SwitchListTile(
                    title: Text('تثبيت', style: TextStyle(fontSize: isMobile ? 13 : 14, color: isPinned ? _primaryColor : null)),
                    subtitle: Text(isPinned ? 'سيبقى في أعلى القائمة' : 'ترتيب عادي', style: TextStyle(fontSize: isMobile ? 11 : 12)),
                    value: isPinned,
                    onChanged: (v) => setDialogState(() => isPinned = v),
                    activeColor: _primaryColor,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    secondary: Icon(Icons.push_pin_rounded, size: 20, color: isPinned ? _primaryColor : Colors.grey.shade400),
                  ),
                ],
              ),
            );

            // أزرار الحوار
            final actions = Row(
              children: [
                TextButton(onPressed: isSaving ? null : () => Navigator.pop(ctx), child: const Text('إلغاء')),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: isSaving ? null : () => _handleSave(ctx, setDialogState, isEdit: isEdit, announcement: announcement, titleCtrl: titleCtrl, bodyCtrl: bodyCtrl, targetType: targetType, targetValue: targetValue, isPublished: isPublished, isUrgent: isUrgent, isPinned: isPinned, expiresAt: expiresAt, imageUrl: imageUrl, imageFile: imageFile, selectedUsers: selectedUsers, setIsSaving: (v) => setDialogState(() => isSaving = v)),
                  icon: isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Icon(isEdit ? Icons.save : Icons.send, size: 18),
                  label: Text(isEdit ? 'حفظ' : 'نشر', style: TextStyle(fontSize: isMobile ? 13 : 14)),
                  style: ElevatedButton.styleFrom(backgroundColor: _primaryColor, foregroundColor: Colors.white),
                ),
              ],
            );

            // على الهاتف: FullScreenDialog — على سطح المكتب: AlertDialog
            if (isMobile) {
              return Directionality(
                textDirection: TextDirection.rtl,
                child: Scaffold(
                  appBar: AppBar(
                    title: Text(isEdit ? 'تعديل إعلان' : 'إعلان جديد', style: const TextStyle(fontSize: 16)),
                    backgroundColor: _primaryColor,
                    foregroundColor: Colors.white,
                    leading: IconButton(icon: const Icon(Icons.close), onPressed: isSaving ? null : () => Navigator.pop(ctx)),
                    actions: [
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: ElevatedButton.icon(
                          onPressed: isSaving ? null : () => _handleSave(ctx, setDialogState, isEdit: isEdit, announcement: announcement, titleCtrl: titleCtrl, bodyCtrl: bodyCtrl, targetType: targetType, targetValue: targetValue, isPublished: isPublished, isUrgent: isUrgent, isPinned: isPinned, expiresAt: expiresAt, imageUrl: imageUrl, imageFile: imageFile, selectedUsers: selectedUsers, setIsSaving: (v) => setDialogState(() => isSaving = v)),
                          icon: isSaving ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Icon(isEdit ? Icons.save : Icons.send, size: 16),
                          label: Text(isEdit ? 'حفظ' : 'نشر', style: const TextStyle(fontSize: 13)),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: _primaryColor, elevation: 0),
                        ),
                      ),
                    ],
                  ),
                  body: dialogContent,
                ),
              );
            }

            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                title: Row(children: [
                  Icon(isEdit ? Icons.edit : Icons.add_circle, color: _primaryColor),
                  const SizedBox(width: 8),
                  Text(isEdit ? 'تعديل إعلان' : 'إعلان جديد'),
                ]),
                content: SizedBox(width: 500, child: dialogContent),
                actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                actions: [actions],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _handleSave(
    BuildContext ctx,
    StateSetter setDialogState, {
    required bool isEdit,
    Map<String, dynamic>? announcement,
    required TextEditingController titleCtrl,
    required TextEditingController bodyCtrl,
    required int targetType,
    String? targetValue,
    required bool isPublished,
    required bool isUrgent,
    required bool isPinned,
    DateTime? expiresAt,
    String? imageUrl,
    File? imageFile,
    required List<Map<String, dynamic>> selectedUsers,
    required void Function(bool) setIsSaving,
  }) async {
    if (titleCtrl.text.trim().isEmpty || bodyCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('العنوان والمحتوى مطلوبان'), backgroundColor: Colors.red));
      return;
    }
    setIsSaving(true);

    String? finalImageUrl = imageUrl;
    if (imageFile != null) finalImageUrl = await AnnouncementService.instance.uploadImage(imageFile);

    Map<String, dynamic> result;
    if (isEdit) {
      result = await AnnouncementService.instance.updateAnnouncement(
        id: announcement!['id'], title: titleCtrl.text.trim(), body: bodyCtrl.text.trim(),
        imageUrl: finalImageUrl, targetType: targetType, targetValue: targetValue,
        isPublished: isPublished, isUrgent: isUrgent, isPinned: isPinned, expiresAt: expiresAt,
        targetUserIds: targetType == 4 ? selectedUsers.map((u) => u['userId'].toString()).toList() : null,
      );
    } else {
      result = await AnnouncementService.instance.createAnnouncement(
        title: titleCtrl.text.trim(), body: bodyCtrl.text.trim(),
        imageUrl: finalImageUrl, targetType: targetType, targetValue: targetValue,
        isPublished: isPublished, isUrgent: isUrgent, isPinned: isPinned, expiresAt: expiresAt,
        targetUserIds: targetType == 4 ? selectedUsers.map((u) => u['userId'].toString()).toList() : null,
      );
    }

    if (ctx.mounted) {
      Navigator.pop(ctx);
      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isEdit ? 'تم تعديل الإعلان' : 'تم إنشاء الإعلان'), backgroundColor: _successColor));
        _loadAnnouncements();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('حدث خطأ'), backgroundColor: Colors.red));
      }
    }
  }

  Widget _buildCustomUserPicker(List<Map<String, dynamic>> selectedUsers, StateSetter setDialogState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _showEmployeePicker(selectedUsers, setDialogState),
          icon: const Icon(Icons.person_add, size: 18),
          label: Text('اختيار موظفين (${selectedUsers.length} محدد)', style: TextStyle(fontSize: _isMobile ? 12 : 14)),
        ),
        if (selectedUsers.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(
              spacing: 4, runSpacing: 4,
              children: selectedUsers.map((u) => Chip(
                label: Text(u['name'] ?? u['fullName'] ?? '—', style: TextStyle(fontSize: _isMobile ? 11 : 12)),
                deleteIcon: const Icon(Icons.close, size: 14),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                onDeleted: () => setDialogState(() => selectedUsers.removeWhere((x) => x['userId'] == u['userId'])),
              )).toList(),
            ),
          ),
      ],
    );
  }

  Future<void> _showEmployeePicker(List<Map<String, dynamic>> selectedUsers, StateSetter parentSetState) async {
    List<Map<String, dynamic>> employees = [];
    bool loading = true;
    String search = '';

    final companyId = VpsAuthService.instance.currentCompanyId;
    if (companyId == null) return;

    final isMobile = _isMobile;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setPickerState) {
            if (loading) {
              () async {
                try {
                  final response = await ApiClient.instance.getRaw('/companies/$companyId/employees?pageSize=500');
                  final data = response?['data'];
                  if (data is List) employees = data.map((e) => Map<String, dynamic>.from(e)).toList();
                } catch (_) {}
                if (ctx.mounted) setPickerState(() => loading = false);
              }();
            }

            final filtered = search.isEmpty ? employees : employees.where((e) {
              final name = (e['fullName'] ?? '').toString().toLowerCase();
              return name.contains(search.toLowerCase());
            }).toList();

            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                title: Text('اختيار موظفين', style: TextStyle(fontSize: isMobile ? 16 : 20)),
                contentPadding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 24, vertical: 8),
                content: SizedBox(
                  width: isMobile ? double.maxFinite : 400,
                  height: isMobile ? MediaQuery.of(ctx).size.height * 0.5 : 400,
                  child: Column(
                    children: [
                      TextField(
                        decoration: InputDecoration(hintText: 'بحث...', prefixIcon: const Icon(Icons.search), border: const OutlineInputBorder(), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: isMobile ? 8 : 12)),
                        style: TextStyle(fontSize: isMobile ? 13 : 14),
                        onChanged: (v) => setPickerState(() => search = v),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: loading
                            ? const Center(child: CircularProgressIndicator())
                            : ListView.builder(
                                itemCount: filtered.length,
                                itemBuilder: (_, i) {
                                  final emp = filtered[i];
                                  final empId = emp['id']?.toString() ?? '';
                                  final isSelected = selectedUsers.any((u) => u['userId']?.toString() == empId);
                                  return CheckboxListTile(
                                    title: Text(emp['fullName'] ?? '—', style: TextStyle(fontSize: isMobile ? 13 : 14)),
                                    subtitle: Text(emp['department'] ?? '', style: TextStyle(fontSize: isMobile ? 11 : 12)),
                                    value: isSelected,
                                    onChanged: (checked) {
                                      setPickerState(() {
                                        if (checked == true) { selectedUsers.add({'userId': empId, 'name': emp['fullName']}); }
                                        else { selectedUsers.removeWhere((u) => u['userId']?.toString() == empId); }
                                      });
                                    },
                                    dense: true,
                                    controlAffinity: ListTileControlAffinity.leading,
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () { parentSetState(() {}); Navigator.pop(ctx); },
                    child: Text('تم (${selectedUsers.length})', style: TextStyle(fontSize: isMobile ? 13 : 14)),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// تقرير القراءة — من قرأ ومن لم يقرأ
  Future<void> _showReadReport(dynamic id) async {
    final annId = id is int ? id : int.tryParse(id.toString()) ?? 0;
    final isMobile = _isMobile;

    showDialog(
      context: context,
      builder: (ctx) {
        return FutureBuilder<Map<String, dynamic>>(
          future: AnnouncementService.instance.getReadReport(annId),
          builder: (ctx, snapshot) {
            final loading = snapshot.connectionState == ConnectionState.waiting;
            final data = snapshot.data?['data'] as Map<String, dynamic>?;
            final readUsers = (data?['readUsers'] as List?)?.cast<Map<String, dynamic>>() ?? [];
            final notReadUsers = (data?['notReadUsers'] as List?)?.cast<Map<String, dynamic>>() ?? [];
            final totalRead = data?['totalRead'] ?? 0;
            final totalNotRead = data?['totalNotRead'] ?? 0;

            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                title: Row(children: [
                  const Icon(Icons.analytics, color: _primaryColor, size: 22),
                  const SizedBox(width: 8),
                  Text('تقرير القراءة', style: TextStyle(fontSize: isMobile ? 16 : 18)),
                ]),
                contentPadding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 20, vertical: 8),
                content: SizedBox(
                  width: isMobile ? double.maxFinite : 400,
                  height: isMobile ? MediaQuery.of(ctx).size.height * 0.5 : 400,
                  child: loading
                      ? const Center(child: CircularProgressIndicator())
                      : DefaultTabController(
                          length: 2,
                          child: Column(
                            children: [
                              TabBar(
                                labelColor: _primaryColor,
                                unselectedLabelColor: Colors.grey,
                                labelStyle: TextStyle(fontSize: isMobile ? 12 : 14, fontWeight: FontWeight.bold),
                                tabs: [
                                  Tab(text: 'قرأ ($totalRead)'),
                                  Tab(text: 'لم يقرأ ($totalNotRead)'),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Expanded(
                                child: TabBarView(
                                  children: [
                                    _buildUserList(readUsers, isRead: true, isMobile: isMobile),
                                    _buildUserList(notReadUsers, isRead: false, isMobile: isMobile),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildUserList(List<Map<String, dynamic>> users, {required bool isRead, required bool isMobile}) {
    if (users.isEmpty) {
      return Center(
        child: Text(isRead ? 'لا أحد قرأ بعد' : 'الجميع قرأ', style: TextStyle(color: Colors.grey, fontSize: isMobile ? 13 : 14)),
      );
    }
    return ListView.builder(
      itemCount: users.length,
      itemBuilder: (_, i) {
        final u = users[i];
        final name = u['name']?.toString() ?? u['fullName']?.toString() ?? '—';
        final readAt = u['readAt']?.toString();
        return ListTile(
          dense: true,
          leading: CircleAvatar(
            radius: isMobile ? 14 : 16,
            backgroundColor: isRead ? _successColor.withOpacity(0.15) : _dangerColor.withOpacity(0.15),
            child: Icon(isRead ? Icons.check : Icons.schedule, size: isMobile ? 14 : 16, color: isRead ? _successColor : _dangerColor),
          ),
          title: Text(name, style: TextStyle(fontSize: isMobile ? 13 : 14)),
          subtitle: isRead && readAt != null
              ? Text(_formatDate(readAt), style: TextStyle(fontSize: isMobile ? 10 : 11, color: Colors.grey))
              : null,
        );
      },
    );
  }

  String _formatDate(String dateStr) {
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return dateStr;
    }
  }

  Future<void> _confirmDelete(dynamic id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('تأكيد الحذف', style: TextStyle(fontSize: _isMobile ? 16 : 20)),
          content: const Text('هل أنت متأكد من حذف هذا الإعلان؟'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: _dangerColor, foregroundColor: Colors.white),
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      final success = await AnnouncementService.instance.deleteAnnouncement(id is int ? id : int.tryParse(id.toString()) ?? 0);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(success ? 'تم حذف الإعلان' : 'حدث خطأ في الحذف'),
          backgroundColor: success ? _successColor : _dangerColor,
        ));
        if (success) _loadAnnouncements();
      }
    }
  }
}
