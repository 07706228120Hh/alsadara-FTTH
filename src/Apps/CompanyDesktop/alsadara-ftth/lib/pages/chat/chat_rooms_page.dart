import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/chat_service.dart';
import '../../services/vps_auth_service.dart';
import '../../permissions/permission_manager.dart';
import '../../frontend/frontend.dart';
import 'chat_conversation_page.dart';

/// صفحة قائمة غرف المحادثة — تدعم سطح المكتب والموبايل
class ChatRoomsPage extends StatefulWidget {
  final bool embeddedMode;

  const ChatRoomsPage({super.key, this.embeddedMode = false});

  @override
  State<ChatRoomsPage> createState() => _ChatRoomsPageState();
}

class _ChatRoomsPageState extends State<ChatRoomsPage> {
  // ═══ Constants ═══
  static const _desktopBreakpoint = 768.0;
  static const _sidebarWidth = 350.0;

  // ═══ State ═══
  List<Map<String, dynamic>> _rooms = [];
  List<Map<String, dynamic>> _filteredRooms = [];
  bool _isLoading = true;
  bool _hasError = false;
  String _searchQuery = '';
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  // ═══ Desktop split view ═══
  Map<String, dynamic>? _selectedRoom;

  // ═══ Admin ═══
  bool get _isAdmin {
    final role = VpsAuthService.instance.currentUser?.role ?? '';
    return role == 'CompanyAdmin' || role == 'Admin' || role == 'SuperAdmin';
  }

  // ═══ Streams ═══
  StreamSubscription<Map<String, dynamic>>? _messageSub;
  StreamSubscription<Map<String, dynamic>>? _readSub;
  StreamSubscription<Map<String, dynamic>>? _roomEventSub;
  StreamSubscription<Map<String, dynamic>>? _deletedSub;

  // ═══ Online users ═══
  final Set<String> _onlineUserIds = {};
  StreamSubscription<Map<String, dynamic>>? _onlineSub;

  @override
  void initState() {
    super.initState();
    _loadRooms();
    _subscribeToStreams();
    _fetchOnlineUsers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _messageSub?.cancel();
    _readSub?.cancel();
    _roomEventSub?.cancel();
    _deletedSub?.cancel();
    _onlineSub?.cancel();
    super.dispose();
  }

  // ═══════════════════════════════════════
  // Data Loading
  // ═══════════════════════════════════════

  Future<void> _loadRooms() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final rooms = await ChatService.instance.getRooms();
      // ترتيب حسب آخر رسالة
      rooms.sort((a, b) {
        final aTime = a['lastMessageAt'] ?? a['updatedAt'] ?? '';
        final bTime = b['lastMessageAt'] ?? b['updatedAt'] ?? '';
        return bTime.toString().compareTo(aTime.toString());
      });

      if (!mounted) return;
      setState(() {
        _rooms = rooms;
        _isLoading = false;
        _applyFilter();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  void _applyFilter() {
    if (_searchQuery.isEmpty) {
      _filteredRooms = List.from(_rooms);
    } else {
      final q = _searchQuery.toLowerCase();
      _filteredRooms = _rooms.where((room) {
        final name = _getRoomDisplayName(room).toLowerCase();
        final lastMsg = (room['lastMessagePreview'] ?? '').toString().toLowerCase();
        return name.contains(q) || lastMsg.contains(q);
      }).toList();
    }
  }

  void _subscribeToStreams() {
    final chat = ChatService.instance;

    // رسالة جديدة → تحديث آخر رسالة + إعادة ترتيب
    _messageSub = chat.onMessage.listen((msg) {
      if (!mounted) return;
      final roomId = msg['roomId']?.toString();
      if (roomId == null) return;

      setState(() {
        final idx = _rooms.indexWhere((r) => r['id']?.toString() == roomId);
        if (idx >= 0) {
          _rooms[idx]['lastMessagePreview'] = msg['content'];
          _rooms[idx]['lastMessageSenderName'] = msg['senderName'];
          _rooms[idx]['lastMessageAt'] = msg['sentAt'] ?? DateTime.now().toIso8601String();
          // زيادة عدد الغير مقروء إذا لم تكن الغرفة المفتوحة حاليا
          if (_selectedRoom == null || _selectedRoom!['id']?.toString() != roomId) {
            _rooms[idx]['unreadCount'] = (_rooms[idx]['unreadCount'] ?? 0) + 1;
          }
          // نقل الغرفة للأعلى
          final room = _rooms.removeAt(idx);
          _rooms.insert(0, room);
        } else {
          // غرفة جديدة — أعد التحميل
          _loadRooms();
          return;
        }
        _applyFilter();
      });
    });

    // تحديث القراءة
    _readSub = chat.onRead.listen((data) {
      if (!mounted) return;
      final roomId = data['roomId']?.toString();
      if (roomId == null) return;

      final currentUserId = VpsAuthService.instance.currentUser?.id;
      if (data['userId']?.toString() == currentUserId) {
        setState(() {
          final idx = _rooms.indexWhere((r) => r['id']?.toString() == roomId);
          if (idx >= 0) {
            _rooms[idx]['unreadCount'] = 0;
            _applyFilter();
          }
        });
      }
    });

    // حذف رسالة
    _deletedSub = chat.onDeleted.listen((data) {
      if (!mounted) return;
      // لا حاجة لتحديث كبير — فقط أعد التحميل لتحديث آخر رسالة
      _loadRooms();
    });

    // إضافة/إزالة من غرفة
    _roomEventSub = chat.onRoomEvent.listen((data) {
      if (!mounted) return;
      _loadRooms();
    });

    // حالة الاتصال
    _onlineSub = chat.onOnlineStatus.listen((data) {
      if (!mounted) return;
      final userId = data['userId']?.toString();
      if (userId == null) return;
      setState(() {
        if (data['isOnline'] == true) {
          _onlineUserIds.add(userId);
        } else {
          _onlineUserIds.remove(userId);
        }
      });
    });
  }

  Future<void> _fetchOnlineUsers() async {
    try {
      final users = await ChatService.instance.getOnlineUsers();
      if (mounted) {
        setState(() => _onlineUserIds.addAll(users));
      }
    } catch (_) {}
  }

  // ═══════════════════════════════════════
  // Helpers
  // ═══════════════════════════════════════

  String _getRoomDisplayName(Map<String, dynamic> room) {
    final type = room['type'] ?? 0;
    // محادثة خاصة: اسم المستخدم الآخر
    if (type == 0) {
      return room['otherUserName']?.toString() ??
          room['name']?.toString() ??
          'محادثة خاصة';
    }
    return room['name']?.toString() ?? _roomTypeLabel(type);
  }

  String _roomTypeLabel(int type) {
    switch (type) {
      case 0:
        return 'محادثة خاصة';
      case 1:
        return 'قسم';
      case 2:
        return 'بث';
      case 3:
        return 'مجموعة';
      default:
        return 'محادثة';
    }
  }

  IconData _roomTypeIcon(int type) {
    switch (type) {
      case 0:
        return Icons.person;
      case 1:
        return Icons.groups;
      case 2:
        return Icons.campaign;
      case 3:
        return Icons.group;
      default:
        return Icons.chat;
    }
  }

  Color _roomTypeColor(int type) {
    switch (type) {
      case 0:
        return SdColors.primary;
      case 1:
        return SdColors.accent;
      case 2:
        return SdColors.warning;
      case 3:
        return SdColors.info;
      default:
        return SdColors.primary;
    }
  }

  String _previewWithIcon(String msg) {
    if (msg.startsWith('/uploads/chat/') || msg.startsWith('http')) {
      if (msg.contains('.jpg') || msg.contains('.jpeg') || msg.contains('.png') || msg.contains('.webp')) return '📷 صورة';
      if (msg.contains('.mp3') || msg.contains('.aac') || msg.contains('.wav') || msg.contains('.m4a') || msg.contains('.ogg')) return '🎤 صوت';
      if (msg.contains('.pdf') || msg.contains('.doc') || msg.contains('.xls') || msg.contains('.zip')) return '📎 ملف';
      return '📎 مرفق';
    }
    if (msg.startsWith('{') && (msg.contains('"lat"') || msg.contains('"lng"'))) return '📍 موقع';
    if (msg.startsWith('{') && (msg.contains('"name"') || msg.contains('"phone"'))) return '👤 جهة اتصال';
    if (msg == '📷 صورة' || msg == '🎤 صوت' || msg == '📍 موقع' || msg == '👤 جهة اتصال' || msg == '📎 ملف') return msg;
    return msg;
  }

  bool _isMe(String name) {
    final myName = VpsAuthService.instance.currentUser?.fullName ?? '';
    return name == myName;
  }

  String _formatTime(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '';
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final msgDay = DateTime(dt.year, dt.month, dt.day);
      final dayDiff = today.difference(msgDay).inDays;

      if (dayDiff == 0) {
        return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } else if (dayDiff == 1) {
        return 'أمس';
      } else if (dayDiff < 7) {
        const days = ['الاحد', 'الاثنين', 'الثلاثاء', 'الاربعاء', 'الخميس', 'الجمعة', 'السبت'];
        return days[dt.weekday % 7];
      } else {
        return '${dt.day}/${dt.month}/${dt.year}';
      }
    } catch (_) {
      return '';
    }
  }

  bool get _isDesktop {
    final width = MediaQuery.of(context).size.width;
    return width > _desktopBreakpoint;
  }

  // ═══════════════════════════════════════
  // Room Selection
  // ═══════════════════════════════════════

  /// عرض كل محادثات الشركة (مدير فقط)
  Future<void> _showAllCompanyRooms() async {
    final rooms = await ChatService.instance.getAllCompanyRooms();
    if (!mounted) return;

    final typeLabel = {0: 'خاصة', 1: 'قسم', 2: 'بث', 3: 'مجموعة'};

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Row(
            children: [
              const Expanded(child: Text('كل محادثات الشركة', style: TextStyle(fontSize: 16))),
              Text('${rooms.length}', style: TextStyle(fontSize: 13, color: SdColors.muted)),
              const SizedBox(width: 8),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: MediaQuery.of(ctx).size.height * 0.6,
            child: rooms.isEmpty
                ? const Center(child: Text('لا توجد محادثات'))
                : ListView.builder(
                    itemCount: rooms.length,
                    itemBuilder: (_, i) {
                      final r = rooms[i];
                      final type = r['type'] ?? 0;
                      final name = r['name']?.toString() ?? '';
                      final members = (r['memberNames'] as List?)?.join('، ') ?? '';
                      final displayName = name.isNotEmpty ? name : members;
                      final msgCount = r['messageCount'] ?? 0;
                      final memberCount = r['memberCount'] ?? 0;

                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 18,
                          backgroundColor: type == 0 ? SdColors.primaryTint : type == 2 ? SdColors.warningTint : SdColors.accentTint,
                          child: Icon(
                            type == 0 ? Icons.person : type == 1 ? Icons.groups : type == 2 ? Icons.campaign : Icons.group,
                            size: 18,
                            color: type == 0 ? SdColors.primary : type == 2 ? SdColors.warning : SdColors.accent,
                          ),
                        ),
                        title: Text(displayName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          '${typeLabel[type] ?? ''} • $memberCount عضو • $msgCount رسالة',
                          style: TextStyle(fontSize: 11, color: SdColors.muted),
                        ),
                        trailing: Text(
                          r['lastMessageAt'] != null ? _formatTime(r['lastMessageAt'].toString()) : '',
                          style: TextStyle(fontSize: 10, color: SdColors.faint),
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          // فتح المحادثة
                          final roomId = r['id']?.toString() ?? '';
                          if (_isDesktop) {
                            setState(() => _selectedRoom = r);
                          } else {
                            Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => ChatConversationPage(
                                roomId: roomId,
                                roomName: displayName,
                                roomType: type,
                              ),
                            ));
                          }
                        },
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }

  /// خيارات المحادثة (ضغط مطوّل)
  void _showRoomOptions(Map<String, dynamic> room) {
    final roomName = _getRoomDisplayName(room);
    final roomId = room['id']?.toString() ?? '';
    final isPinned = room['isPinned'] == true;
    final isMuted = room['isMuted'] == true;
    final userRole = VpsAuthService.instance.currentUser?.role ?? '';
    final isAdmin = userRole == 'CompanyAdmin' || userRole == 'Admin' || userRole == 'SuperAdmin' || userRole == 'Manager';

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // تثبيت / إلغاء التثبيت
              ListTile(
                leading: Icon(isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                    color: isPinned ? SdColors.warning : SdColors.muted),
                title: Text(isPinned ? 'إلغاء التثبيت' : 'تثبيت المحادثة'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await ChatService.instance.togglePin(roomId, !isPinned);
                  _loadRooms();
                  _showSnackBar(isPinned ? 'تم إلغاء التثبيت' : 'تم تثبيت المحادثة');
                },
              ),
              // كتم / إلغاء الكتم
              ListTile(
                leading: Icon(isMuted ? Icons.notifications_active : Icons.notifications_off,
                    color: isMuted ? SdColors.success : SdColors.muted),
                title: Text(isMuted ? 'تفعيل الإشعارات' : 'كتم الإشعارات'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await ChatService.instance.toggleMute(roomId, !isMuted);
                  _loadRooms();
                  _showSnackBar(isMuted ? 'تم تفعيل الإشعارات' : 'تم كتم الإشعارات');
                },
              ),
              // حذف (مدير فقط)
              if (isAdmin)
                ListTile(
                  leading: const Icon(Icons.delete_forever, color: SdColors.danger),
                  title: const Text('حذف المحادثة', style: TextStyle(color: SdColors.danger)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (c) => Directionality(
                        textDirection: TextDirection.rtl,
                        child: AlertDialog(
                          title: const Text('حذف المحادثة'),
                          content: Text('هل أنت متأكد من حذف "$roomName"؟'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
                            TextButton(onPressed: () => Navigator.pop(c, true),
                              child: const Text('حذف', style: TextStyle(color: SdColors.danger, fontWeight: FontWeight.bold))),
                          ],
                        ),
                      ),
                    );
                    if (confirm != true) return;
                    final ok = await ChatService.instance.deleteRoom(roomId);
                    if (ok) {
                      if (_selectedRoom?['id']?.toString() == roomId) setState(() => _selectedRoom = null);
                      _loadRooms();
                      _showSnackBar('تم حذف المحادثة');
                    } else {
                      _showSnackBar('فقط مدير الشركة يمكنه الحذف');
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _openRoom(Map<String, dynamic> room) {
    // تصفير عدد الغير مقروء
    final roomId = room['id']?.toString() ?? '';
    if (roomId.isNotEmpty) {
      ChatService.instance.markAsRead(roomId);
      setState(() {
        final idx = _rooms.indexWhere((r) => r['id']?.toString() == roomId);
        if (idx >= 0) {
          _rooms[idx]['unreadCount'] = 0;
          _applyFilter();
        }
      });
    }

    if (_isDesktop) {
      setState(() => _selectedRoom = room);
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatConversationPage(
                    roomId: room['id']?.toString() ?? '',
                    roomName: _getRoomDisplayName(room),
                    roomType: room['type'] ?? 0,
                    otherUserId: room['otherUser']?['userId']?.toString(),
                  ),
        ),
      ).then((_) {
        // عند العودة — تحديث القائمة
        _loadRooms();
      });
    }
  }

  // ═══════════════════════════════════════
  // Create Room Actions
  // ═══════════════════════════════════════

  void _showCreateOptions() {
    final pm = PermissionManager.instance;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: SdColors.faint,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        'محادثة جديدة',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // محادثة خاصة — متاح دائما
                  _buildCreateOption(
                    icon: Icons.person_add,
                    color: SdColors.primary,
                    label: 'محادثة خاصة',
                    subtitle: 'محادثة مع موظف',
                    onTap: () {
                      Navigator.pop(ctx);
                      _showUserPicker(roomType: 0);
                    },
                  ),
                  // مجموعة جديدة
                  if (pm.hasAction('chat.create_group', 'add'))
                    _buildCreateOption(
                      icon: Icons.group_add,
                      color: SdColors.info,
                      label: 'مجموعة جديدة',
                      subtitle: 'مجموعة محادثة مع عدة اشخاص',
                      onTap: () {
                        Navigator.pop(ctx);
                        _showCreateGroupDialog();
                      },
                    ),
                  // محادثة قسم
                  if (pm.hasAction('chat.create_department', 'add'))
                    _buildCreateOption(
                      icon: Icons.groups,
                      color: SdColors.accent,
                      label: 'محادثة قسم',
                      subtitle: 'محادثة جماعية لقسم كامل',
                      onTap: () {
                        Navigator.pop(ctx);
                        _showDepartmentPicker();
                      },
                    ),
                  // بث للجميع
                  if (pm.hasAction('chat.create_broadcast', 'add'))
                    _buildCreateOption(
                      icon: Icons.campaign,
                      color: SdColors.warning,
                      label: 'بث للجميع',
                      subtitle: 'ارسال رسالة لجميع الموظفين',
                      onTap: () {
                        Navigator.pop(ctx);
                        _createBroadcastRoom();
                      },
                    ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCreateOption({
    required IconData icon,
    required Color color,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: color, size: 24),
      ),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: TextStyle(color: SdColors.muted, fontSize: 12)),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
    );
  }

  // ═══════════════════════════════════════
  // User Picker (Direct / Group)
  // ═══════════════════════════════════════

  Future<void> _showUserPicker({required int roomType, String? groupName}) async {
    final selected = await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (ctx) => _UserPickerDialog(
        multiSelect: roomType == 3,
        title: roomType == 0 ? 'اختر موظف' : 'اختر الاعضاء',
      ),
    );

    if (selected == null || selected.isEmpty) return;

    if (roomType == 0) {
      // Direct — مستخدم واحد
      final targetId = selected.first['userId']?.toString() ?? selected.first['id']?.toString();
      if (targetId == null) return;
      _createRoom(type: 0, memberIds: [targetId]);
    } else if (roomType == 3 && groupName != null) {
      // Group
      final ids = selected.map((u) => (u['userId'] ?? u['id']).toString()).toList();
      _createRoom(type: 3, name: groupName, memberIds: ids);
    }
  }

  // ═══════════════════════════════════════
  // Department Picker
  // ═══════════════════════════════════════

  Future<void> _showDepartmentPicker() async {
    final departments = await ChatService.instance.getAvailableDepartments();
    if (!mounted) return;
    if (departments.isEmpty) {
      _showSnackBar('لا توجد اقسام متاحة');
      return;
    }

    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('اختر القسم'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: departments.length,
                itemBuilder: (_, i) {
                  final dept = departments[i];
                  final name = dept['nameAr']?.toString() ?? dept['name']?.toString() ?? '';
                  final count = dept['memberCount'] ?? 0;
                  return ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: SdColors.accent,
                      radius: 18,
                      child: Icon(Icons.groups, color: Colors.white, size: 18),
                    ),
                    title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('$count موظف', style: TextStyle(fontSize: 12, color: SdColors.muted)),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                    onTap: () => Navigator.pop(ctx, dept),
                  );
                },
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ],
          ),
        );
      },
    );

    if (selected == null || !mounted) return;
    final deptId = selected['id'];
    final deptName = selected['nameAr']?.toString() ?? selected['name']?.toString() ?? '';
    final memberCount = selected['memberCount'] ?? 0;
    if (deptId == null) return;

    // تأكيد الإنشاء
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('محادثة قسم "$deptName"'),
          content: Text('سيتم إنشاء محادثة وإضافة جميع موظفي القسم ($memberCount موظف) تلقائياً.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('إنشاء')),
          ],
        ),
      ),
    );
    if (confirm != true) return;

    _createRoom(type: 1, departmentId: deptId is int ? deptId : int.tryParse(deptId.toString()));
  }

  // ═══════════════════════════════════════
  // Create Group Dialog
  // ═══════════════════════════════════════

  Future<void> _showCreateGroupDialog() async {
    final nameController = TextEditingController();

    final groupName = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('مجموعة جديدة'),
            content: TextField(
              controller: nameController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'اسم المجموعة',
                hintText: 'مثال: فريق التطوير',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(Icons.group),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('الغاء'),
              ),
              FilledButton(
                onPressed: () {
                  final name = nameController.text.trim();
                  if (name.isNotEmpty) {
                    Navigator.pop(ctx, name);
                  }
                },
                child: const Text('التالي'),
              ),
            ],
          ),
        );
      },
    );

    nameController.dispose();

    if (groupName == null || groupName.isEmpty) return;
    _showUserPicker(roomType: 3, groupName: groupName);
  }

  // ═══════════════════════════════════════
  // Create Broadcast Room
  // ═══════════════════════════════════════

  Future<void> _createBroadcastRoom() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('بث للجميع'),
            content: const Text(
              'سيتم انشاء غرفة بث لجميع الموظفين.\nهل انت متاكد؟',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('الغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('انشاء'),
              ),
            ],
          ),
        );
      },
    );

    if (confirm != true) return;
    _createRoom(type: 2, name: 'بث عام');
  }

  // ═══════════════════════════════════════
  // API: Create Room
  // ═══════════════════════════════════════

  Future<void> _createRoom({
    required int type,
    String? name,
    int? departmentId,
    List<String>? memberIds,
  }) async {
    _showSnackBar('جاري الانشاء...', duration: 1);

    final result = await ChatService.instance.createRoomPost(
      type: type,
      name: name,
      departmentId: departmentId,
      memberIds: memberIds,
    );

    if (!mounted) return;

    if (result != null) {
      _showSnackBar('تم انشاء المحادثة');
      await _loadRooms();

      // فتح الغرفة الجديدة
      final roomId = result['id']?.toString() ?? result['roomId']?.toString();
      if (roomId != null) {
        final newRoom = _rooms.firstWhere(
          (r) => r['id']?.toString() == roomId,
          orElse: () => result,
        );
        _openRoom(newRoom);
      }
    } else {
      _showSnackBar('فشل انشاء المحادثة');
    }
  }

  void _showSnackBar(String msg, {int duration = 2}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, textDirection: TextDirection.rtl),
        duration: Duration(seconds: duration),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ═══════════════════════════════════════
  // Build
  // ═══════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final isDesktop = _isDesktop;

    if (widget.embeddedMode) {
      return _buildRoomsList();
    }

    return SdPage(
      appBar: _buildAppBar(),
      scrollable: false,
      padding: EdgeInsets.zero,
      maxWidth: double.infinity,
      body: isDesktop ? _buildDesktopLayout() : _buildRoomsList(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return SdAppBar(
      title: 'المحادثات',
      actions: [
        // زر كل المحادثات (مدير فقط)
        if (_isAdmin)
          SdAppBarAction(
            icon: Icons.admin_panel_settings_outlined,
            label: 'كل محادثات الشركة',
            onPressed: _showAllCompanyRooms,
          ),
        SdAppBarAction(
          icon: Icons.add_comment_outlined,
          label: 'محادثة جديدة',
          onPressed: _showCreateOptions,
        ),
      ],
    );
  }

  // ═══════════════════════════════════════
  // Desktop Layout (Split View)
  // ═══════════════════════════════════════

  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // قائمة الغرف
        SizedBox(
          width: _sidebarWidth,
          child: Container(
            margin: const EdgeInsetsDirectional.fromSTEB(12, 12, 0, 12),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: SdColors.surface,
              borderRadius: BorderRadius.circular(SdRadius.xl),
              border: SdOutline.all,
              boxShadow: SdDepth.raised(),
            ),
            child: _buildRoomsList(),
          ),
        ),
        // المحادثة
        Expanded(
          child: _selectedRoom != null
              ? ChatConversationPage(
                  key: ValueKey(_selectedRoom!['id']?.toString()),
                  roomId: _selectedRoom!['id']?.toString() ?? '',
                  roomName: _getRoomDisplayName(_selectedRoom!),
                  roomType: _selectedRoom!['type'] ?? 0,
                  otherUserId: _selectedRoom!['otherUser']?['userId']?.toString(),
                )
              : _buildEmptyConversation(),
        ),
      ],
    );
  }

  Widget _buildEmptyConversation() {
    return Container(
      color: SdColors.ground,
      child: const Center(
        child: SdEmptyState(
          icon: Icons.chat_bubble_outline,
          title: 'اختر محادثة للبدء',
        ),
      ),
    );
  }

  // ═══════════════════════════════════════
  // Rooms List
  // ═══════════════════════════════════════

  Widget _buildRoomsList() {
    return Column(
      children: [
        _buildSearchBar(),
        Divider(height: 0.5, thickness: 0.5, color: SdColors.divider),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: SdColors.primary))
              : _hasError
                  ? _buildErrorState()
                  : _filteredRooms.isEmpty
                      ? _buildEmptyState()
                      : RefreshIndicator(
                          onRefresh: _loadRooms,
                          color: SdColors.primary,
                          child: ListView.builder(
                            controller: _scrollController,
                            physics: const AlwaysScrollableScrollPhysics(),
                            itemCount: _filteredRooms.length,
                            itemBuilder: (_, i) => _buildRoomTile(_filteredRooms[i]),
                          ),
                        ),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return Container(
      color: SdColors.surface,
      padding: EdgeInsets.fromLTRB(isMobile ? 10 : 16, 6, isMobile ? 10 : 16, 6),
      child: SizedBox(
        height: isMobile ? 38 : 42,
        child: TextField(
          controller: _searchController,
          textDirection: TextDirection.rtl,
          style: TextStyle(fontSize: isMobile ? 13 : 14),
          decoration: InputDecoration(
            hintText: 'بحث...',
            hintStyle: TextStyle(color: SdColors.faint, fontSize: isMobile ? 13 : 14),
            prefixIcon: Icon(Icons.search, color: SdColors.faint, size: isMobile ? 20 : 22),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.close, size: isMobile ? 18 : 20),
                    onPressed: () {
                      _searchController.clear();
                      setState(() { _searchQuery = ''; _applyFilter(); });
                    },
                  )
                : null,
            filled: true,
            fillColor: SdColors.ground,
            contentPadding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 16, vertical: 0),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
          ),
          onChanged: (val) { setState(() { _searchQuery = val; _applyFilter(); }); },
        ),
      ),
    );
  }

  Widget _buildRoomTile(Map<String, dynamic> room) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final roomId = room['id']?.toString() ?? '';
    final type = room['type'] ?? 0;
    final name = _getRoomDisplayName(room);
    final lastMsg = room['lastMessagePreview']?.toString() ?? '';
    final lastMsgSender = room['lastMessageSenderName']?.toString() ?? '';
    final lastMsgTime = room['lastMessageAt']?.toString() ?? room['updatedAt']?.toString();
    final unreadCount = room['unreadCount'] ?? 0;
    final isSelected = _selectedRoom != null && _selectedRoom!['id']?.toString() == roomId;

    final otherUserId = room['otherUserId']?.toString();
    final isOnline = otherUserId != null && _onlineUserIds.contains(otherUserId);

    return Material(
      color: isSelected ? SdColors.primaryTint : SdColors.surface,
      child: InkWell(
        onTap: () => _openRoom(room),
        onLongPress: () => _showRoomOptions(room),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 12 : 16,
            vertical: isMobile ? 8 : 12,
          ),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: SdColors.divider, width: 0.5),
            ),
          ),
          child: Row(
            children: [
              _buildAvatar(type, name, isOnline: type == 0 && isOnline),
              SizedBox(width: isMobile ? 10 : 12),
              // المحتوى
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // الاسم + الوقت
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: TextStyle(
                              fontSize: isMobile ? 14 : 15,
                              fontWeight: unreadCount > 0 ? FontWeight.w700 : FontWeight.w600,
                              color: SdColors.ink,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (lastMsgTime != null && lastMsgTime.isNotEmpty)
                          Text(
                            _formatTime(lastMsgTime),
                            style: TextStyle(
                              fontSize: 11,
                              color: unreadCount > 0 ? SdColors.primary : SdColors.muted,
                              fontWeight: unreadCount > 0 ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: isMobile ? 2 : 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            lastMsg.isNotEmpty
                                ? (lastMsgSender.isNotEmpty
                                    ? '${_isMe(lastMsgSender) ? 'أنت' : lastMsgSender}: ${_previewWithIcon(lastMsg)}'
                                    : _previewWithIcon(lastMsg))
                                : (type != 0 ? '${room['memberCount'] ?? 0} عضو' : 'لا توجد رسائل بعد'),
                            style: TextStyle(
                              fontSize: isMobile ? 12 : 13,
                              color: unreadCount > 0 ? SdColors.muted : SdColors.muted,
                              fontWeight: unreadCount > 0 ? FontWeight.w500 : FontWeight.normal,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (room['isPinned'] == true)
                          Padding(
                            padding: const EdgeInsetsDirectional.only(start: 4),
                            child: const Icon(Icons.push_pin, size: 14, color: SdColors.warning),
                          ),
                        if (room['isMuted'] == true)
                          Padding(
                            padding: const EdgeInsetsDirectional.only(start: 4),
                            child: Icon(Icons.notifications_off, size: 14, color: SdColors.faint),
                          ),
                        if (unreadCount > 0) ...[
                          const SizedBox(width: 8),
                          _buildUnreadBadge(unreadCount),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(int type, String name, {bool isOnline = false}) {
    final color = _roomTypeColor(type);
    final icon = _roomTypeIcon(type);
    final initial = name.isNotEmpty ? name.characters.first : '?';
    final isMobile = MediaQuery.of(context).size.width < 600;
    final radius = isMobile ? 22.0 : 26.0;

    return Stack(
      children: [
        CircleAvatar(
          radius: radius,
          backgroundColor: color.withValues(alpha: 0.15),
          child: type == 0
              ? Text(initial, style: TextStyle(fontSize: radius * 0.75, fontWeight: FontWeight.w700, color: color))
              : Icon(icon, color: color, size: radius * 0.9),
        ),
        if (isOnline)
          Positioned(
            bottom: 0,
            left: 0,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: SdColors.success,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildUnreadBadge(int count) {
    return SdBadge(count: count);
  }

  Widget _buildEmptyState() {
    return Center(
      child: SdEmptyState(
        icon: Icons.chat_outlined,
        title: _searchQuery.isNotEmpty ? 'لا توجد نتائج' : 'لا توجد محادثات',
        message: _searchQuery.isEmpty ? 'اضغط + لبدء محادثة جديدة' : null,
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: SdEmptyState(
        icon: Icons.wifi_off,
        status: SdStatus.danger,
        title: 'فشل تحميل المحادثات',
        action: SdButton(
          label: 'اعادة المحاولة',
          icon: Icons.refresh,
          onPressed: _loadRooms,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// User Picker Dialog
// ═══════════════════════════════════════════════════════════════

class _UserPickerDialog extends StatefulWidget {
  final bool multiSelect;
  final String title;

  const _UserPickerDialog({
    required this.multiSelect,
    required this.title,
  });

  @override
  State<_UserPickerDialog> createState() => _UserPickerDialogState();
}

class _UserPickerDialogState extends State<_UserPickerDialog> {
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _filtered = [];
  final Set<String> _selectedIds = {};
  bool _loading = true;
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadUsers({String? search}) async {
    setState(() => _loading = true);
    try {
      final users = await ChatService.instance.getAvailableUsers(search: search);
      if (!mounted) return;
      setState(() {
        _users = users;
        _filtered = users;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _onSearch(String val) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (val.trim().isEmpty) {
        setState(() => _filtered = _users);
      } else {
        _loadUsers(search: val.trim());
      }
    });
  }

  void _toggleUser(Map<String, dynamic> user) {
    final id = user['userId']?.toString() ?? user['id']?.toString() ?? '';
    if (id.isEmpty) return;

    if (widget.multiSelect) {
      setState(() {
        if (_selectedIds.contains(id)) {
          _selectedIds.remove(id);
        } else {
          _selectedIds.add(id);
        }
      });
    } else {
      Navigator.pop(context, [user]);
    }
  }

  void _confirmSelection() {
    if (_selectedIds.isEmpty) return;
    final selected = _users.where((u) => _selectedIds.contains(u['userId']?.toString() ?? u['id']?.toString())).toList();
    Navigator.pop(context, selected);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width > 500 ? 420 : MediaQuery.of(context).size.width * 0.92,
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              // Search
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  controller: _searchCtrl,
                  textDirection: TextDirection.rtl,
                  decoration: InputDecoration(
                    hintText: 'بحث...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    filled: true,
                    fillColor: SdColors.surfaceAlt,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: _onSearch,
                ),
              ),
              // Selection count
              if (widget.multiSelect && _selectedIds.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      'تم اختيار ${_selectedIds.length}',
                      style: const TextStyle(
                        color: SdColors.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              // List
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: SdColors.primary,
                        ),
                      )
                    : _filtered.isEmpty
                        ? Center(
                            child: Text(
                              'لا توجد نتائج',
                              style: TextStyle(color: SdColors.muted),
                            ),
                          )
                        : ListView.builder(
                            itemCount: _filtered.length,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            itemBuilder: (_, i) {
                              final user = _filtered[i];
                              final id = user['userId']?.toString() ?? user['id']?.toString() ?? '';
                              final name = user['fullName']?.toString() ??
                                  user['name']?.toString() ??
                                  user['username']?.toString() ??
                                  '';
                              final subtitle = user['department']?.toString() ??
                                  user['email']?.toString() ??
                                  '';
                              final isSelected = _selectedIds.contains(id);

                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: SdColors.primary
                                      .withValues(alpha: 0.1),
                                  child: Text(
                                    name.isNotEmpty ? name.characters.first : '?',
                                    style: const TextStyle(
                                      color: SdColors.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  name,
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                subtitle: subtitle.isNotEmpty
                                    ? Text(
                                        subtitle,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: SdColors.muted,
                                        ),
                                      )
                                    : null,
                                trailing: widget.multiSelect
                                    ? Checkbox(
                                        value: isSelected,
                                        activeColor: SdColors.primary,
                                        onChanged: (_) => _toggleUser(user),
                                      )
                                    : null,
                                onTap: () => _toggleUser(user),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              );
                            },
                          ),
              ),
              // Actions
              if (widget.multiSelect)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: SdButton(
                          label: 'الغاء',
                          kind: SdButtonKind.secondary,
                          expand: true,
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SdButton(
                          label: 'تاكيد (${_selectedIds.length})',
                          expand: true,
                          onPressed: _selectedIds.isEmpty ? null : _confirmSelection,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
