import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:just_audio/just_audio.dart';
import 'package:intl/intl.dart' as intl;

import '../../services/chat_service.dart';
import '../../services/vps_auth_service.dart';
import '../../permissions/permission_manager.dart';
import 'employee_profile_card.dart';
import '../../ftth/users/quick_search_users_page.dart';
import '../../services/dual_auth_service.dart';

/// ═══════════════════════════════════════════════════════════════
/// صفحة المحادثة — واجهة مشابهة لـ WhatsApp
/// ═══════════════════════════════════════════════════════════════
class ChatConversationPage extends StatefulWidget {
  final String roomId;
  final String roomName;

  /// 0=Direct, 1=Department, 2=Broadcast, 3=Group
  final int roomType;

  /// معرّف المستخدم الآخر (للمحادثات المباشرة)
  final String? otherUserId;

  const ChatConversationPage({
    super.key,
    required this.roomId,
    required this.roomName,
    required this.roomType,
    this.otherUserId,
  });

  @override
  State<ChatConversationPage> createState() => _ChatConversationPageState();
}

class _ChatConversationPageState extends State<ChatConversationPage> {
  // ═══ Constants ═══
  static const _bubbleSentColor = Color(0xFF1976D2);
  static const _bubbleReceivedColor = Color(0xFFFFFFFF);
  static const _bgColor = Color(0xFFECE5DD);
  static const _appBarColor = Color(0xFF075E54);
  static const _inputBarColor = Color(0xFFFFFFFF);

  // ═══ Controllers ═══
  final _scrollController = ScrollController();
  final _textController = TextEditingController();
  final _textFocusNode = FocusNode();

  // ═══ State ═══
  List<Map<String, dynamic>> _messages = [];
  List<Map<String, dynamic>> _roomMembers = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMoreMessages = true;
  int _currentPage = 1;
  static const _pageSize = 50;

  // ═══ Search ═══
  bool _isSearching = false;
  String _searchQuery = '';
  List<int> _searchMatchIndices = [];
  int _currentSearchMatch = -1;
  final _searchController = TextEditingController();

  // ═══ Typing ═══
  final Map<String, String> _typingUsers = {}; // userId → userName
  Timer? _typingDebounce;
  bool _iAmTyping = false;

  // ═══ Reply ═══
  Map<String, dynamic>? _replyToMessage;

  // ═══ Mention ═══
  bool _showMentionDropdown = false;
  String _mentionQuery = '';
  List<Map<String, dynamic>> _filteredMembers = [];
  final List<Map<String, String>> _pendingMentions = []; // {userId, name}

  // ═══ Audio ═══
  bool _isRecording = false;
  final Map<String, AudioPlayer> _audioPlayers = {};

  // ═══ Room name ═══
  String? _editedRoomName;
  String get _displayRoomName => _editedRoomName ?? widget.roomName;

  // ═══ Upload ═══
  bool _isUploading = false;
  String _uploadFileName = '';

  // ═══ Scroll ═══
  bool _showScrollToBottom = false;
  int _newMessagesSinceScrolled = 0;

  // ═══ Online ═══
  bool _isOtherUserOnline = false;
  StreamSubscription? _onlineSub;

  // ═══ Subscriptions ═══
  StreamSubscription? _messageSub;
  StreamSubscription? _typingSub;
  StreamSubscription? _deletedSub;
  StreamSubscription? _readSub;

  // ═══ Current user ═══
  String get _currentUserId =>
      VpsAuthService.instance.currentUser?.id ?? '';

  // ═══ Polling (fallback for SignalR) ═══
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _setupScrollListener();
    _setupStreamListeners();
    await Future.wait([
      _loadMessages(),
      _loadMembers(),
    ]);
    _markAsRead();

    // Polling كل 5 ثوانٍ كـ fallback إذا SignalR غير متصل
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!ChatService.instance.isConnected && mounted) {
        _refreshMessages();
      }
    });
  }

  /// تحديث الرسائل الجديدة بدون إعادة تحميل كل شيء
  Future<void> _refreshMessages() async {
    try {
      final latest = await ChatService.instance.getMessages(widget.roomId, page: 1, pageSize: 10);
      if (!mounted || latest.isEmpty) return;

      bool hasNew = false;
      for (final msg in latest) {
        final msgId = msg['id']?.toString() ?? msg['messageId']?.toString();
        if (msgId == null) continue;
        final exists = _messages.any((m) =>
            (m['id']?.toString() ?? m['messageId']?.toString()) == msgId);
        if (!exists) {
          // إزالة temp messages مطابقة
          final content = msg['content']?.toString();
          _messages.removeWhere((m) =>
              (m['id']?.toString() ?? '').startsWith('temp_') &&
              m['content']?.toString() == content);
          _messages.insert(0, msg);
          hasNew = true;
        }
      }
      if (hasNew && mounted) {
        setState(() {});
        _scrollToBottom();
        _markAsRead();
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _textController.dispose();
    _textFocusNode.dispose();
    _searchController.dispose();
    _pollTimer?.cancel();
    _typingDebounce?.cancel();
    _messageSub?.cancel();
    _typingSub?.cancel();
    _deletedSub?.cancel();
    _readSub?.cancel();
    _onlineSub?.cancel();
    for (final player in _audioPlayers.values) {
      player.dispose();
    }
    if (_iAmTyping) {
      ChatService.instance.stopTyping(widget.roomId);
    }
    super.dispose();
  }

  // ═══════════════════════════════════════
  // Setup
  // ═══════════════════════════════════════

  void _setupScrollListener() {
    _scrollController.addListener(() {
      // ListView reversed: scrolling to "top" means max extent
      if (_scrollController.position.pixels >=
              _scrollController.position.maxScrollExtent - 100 &&
          !_isLoadingMore &&
          _hasMoreMessages) {
        _loadOlderMessages();
      }

      // إظهار/إخفاء زر العودة للأسفل (reversed: 0 = أسفل)
      final shouldShow = _scrollController.position.pixels > 300;
      if (shouldShow != _showScrollToBottom) {
        setState(() {
          _showScrollToBottom = shouldShow;
          if (!shouldShow) _newMessagesSinceScrolled = 0;
        });
      }
    });
  }

  void _setupStreamListeners() {
    final chat = ChatService.instance;

    _messageSub = chat.onMessage.listen((msg) {
      final roomId = msg['roomId']?.toString() ?? msg['chatRoomId']?.toString();
      if (roomId == widget.roomId && mounted) {
        final msgId = msg['id']?.toString() ?? msg['messageId']?.toString();
        // منع التكرار
        if (msgId != null && _messages.any((m) => (m['id']?.toString() ?? m['messageId']?.toString()) == msgId)) {
          return;
        }
        // هل هذه رسالة من نفس المستخدم؟ قد تكون بديلة لـ optimistic temp message
        final senderId = msg['senderId']?.toString();
        final content = msg['content']?.toString();
        setState(() {
          // إزالة الرسالة المؤقتة إن وجدت
          if (senderId == _currentUserId) {
            _messages.removeWhere((m) =>
                (m['id']?.toString() ?? '').startsWith('temp_') &&
                m['content']?.toString() == content);
          }
          _messages.insert(0, msg);
          if (_showScrollToBottom) {
            _newMessagesSinceScrolled++;
          }
        });
        if (!_showScrollToBottom) {
          _scrollToBottom();
        }
        _markAsRead();
      }
    });

    _typingSub = chat.onTyping.listen((data) {
      if (data['roomId'] != widget.roomId) return;
      final userId = data['userId']?.toString() ?? '';
      if (userId == _currentUserId) return;

      if (mounted) {
        setState(() {
          if (data['isTyping'] == true) {
            _typingUsers[userId] = data['userName']?.toString() ?? '';
          } else {
            _typingUsers.remove(userId);
          }
        });
      }
    });

    _deletedSub = chat.onDeleted.listen((data) {
      if (data['roomId'] != widget.roomId) return;
      final msgId = data['messageId']?.toString();
      if (msgId == null) return;
      if (mounted) {
        setState(() {
          _messages.removeWhere(
            (m) => (m['id']?.toString() ?? m['messageId']?.toString()) == msgId,
          );
        });
      }
    });

    _readSub = chat.onRead.listen((data) {
      if (data['roomId'] != widget.roomId) return;
      if (mounted) setState(() {});
    });

    // حالة الأونلاين (للمحادثات الخاصة)
    if (widget.roomType == 0 && widget.otherUserId != null) {
      _onlineSub = chat.onOnlineStatus.listen((data) {
        if (data['userId'] == widget.otherUserId && mounted) {
          setState(() => _isOtherUserOnline = data['isOnline'] == true);
        }
      });
      // جلب حالة الأونلاين الحالية
      chat.getOnlineUsers().then((ids) {
        if (mounted && widget.otherUserId != null) {
          setState(() => _isOtherUserOnline = ids.contains(widget.otherUserId));
        }
      });
    }
  }

  // ═══════════════════════════════════════
  // Data Loading
  // ═══════════════════════════════════════

  Future<void> _loadMessages() async {
    setState(() => _isLoading = true);
    try {
      final msgs = await ChatService.instance.getMessages(
        widget.roomId,
        page: 1,
        pageSize: _pageSize,
      );
      if (mounted) {
        setState(() {
          _messages = msgs;
          _currentPage = 1;
          _hasMoreMessages = msgs.length >= _pageSize;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadOlderMessages() async {
    if (_isLoadingMore || !_hasMoreMessages) return;
    setState(() => _isLoadingMore = true);
    try {
      final nextPage = _currentPage + 1;
      final older = await ChatService.instance.getMessages(
        widget.roomId,
        page: nextPage,
        pageSize: _pageSize,
      );
      if (mounted) {
        setState(() {
          _messages.addAll(older);
          _currentPage = nextPage;
          _hasMoreMessages = older.length >= _pageSize;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _loadMembers() async {
    try {
      final members =
          await ChatService.instance.getRoomMembers(widget.roomId);
      if (mounted) setState(() => _roomMembers = members);
    } catch (_) {}
  }

  void _markAsRead() {
    ChatService.instance.markAsRead(widget.roomId);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ═══════════════════════════════════════
  // Sending
  // ═══════════════════════════════════════

  Future<void> _sendTextMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    _textController.clear();
    _stopTyping();

    final mentionIds =
        _pendingMentions.map((m) => m['userId']!).toList();
    _pendingMentions.clear();
    final replyId = _replyToMessage?['id']?.toString() ??
        _replyToMessage?['messageId']?.toString();

    // عرض الرسالة فوراً (optimistic UI)
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final optimisticMsg = {
      'id': tempId,
      'roomId': widget.roomId,
      'senderId': _currentUserId,
      'senderName': VpsAuthService.instance.currentUser?.fullName ?? '',
      'messageType': 0,
      'content': text,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'isForwarded': false,
    };

    if (mounted) {
      setState(() {
        _messages.insert(0, optimisticMsg);
        _replyToMessage = null;
      });
      _scrollToBottom();
    }

    try {
      await ChatService.instance.sendMessage(
        roomId: widget.roomId,
        content: text,
        messageType: 0,
        replyToMessageId: replyId,
        mentionUserIds: mentionIds.isNotEmpty ? mentionIds : null,
      );
    } catch (e) {
      // وسم الرسالة كفاشلة (مع زر إعادة إرسال)
      if (mounted) {
        setState(() {
          final idx = _messages.indexWhere((m) => m['id'] == tempId);
          if (idx >= 0) {
            _messages[idx]['_status'] = 'failed';
            _messages[idx]['_retryContent'] = text;
            _messages[idx]['_retryReplyId'] = replyId;
            _messages[idx]['_retryMentions'] = mentionIds;
          }
        });
      }
    }
  }

  Future<void> _sendImageMessage() async {
    try {
      // اختيار المصدر: معرض أو كاميرا
      final source = await showModalBottomSheet<ImageSource>(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (ctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_library, color: Colors.purple),
                  title: const Text('المعرض'),
                  onTap: () => Navigator.pop(ctx, ImageSource.gallery),
                ),
                ListTile(
                  leading: const Icon(Icons.camera_alt, color: Colors.blue),
                  title: const Text('الكاميرا'),
                  onTap: () => Navigator.pop(ctx, ImageSource.camera),
                ),
              ],
            ),
          ),
        ),
      );
      if (source == null) return;

      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        imageQuality: 70,
        maxWidth: 1280,
        maxHeight: 1280,
      );
      if (picked == null) return;

      final file = File(picked.path);

      // معاينة الصورة قبل الإرسال
      if (!mounted) return;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            contentPadding: const EdgeInsets.all(8),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(file, fit: BoxFit.contain,
                    height: MediaQuery.of(ctx).size.height * 0.5),
                ),
                const SizedBox(height: 12),
                Text('${(file.lengthSync() / 1024).toStringAsFixed(0)} KB',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.send, size: 18),
                label: const Text('إرسال'),
              ),
            ],
          ),
        ),
      );

      if (confirm != true) return;
      await _uploadAndSend(file, messageType: 1);
    } catch (e) {
      _showError('فشل إرسال الصورة: $e');
    }
  }

  Future<void> _sendFileMessage() async {
    try {
      final result = await FilePicker.platform.pickFiles();
      if (result == null || result.files.isEmpty) return;

      final path = result.files.single.path;
      if (path == null) return;

      final file = File(path);
      final fileName = path.split('/').last.split('\\').last;
      final fileSize = file.lengthSync();
      final sizeStr = fileSize > 1024 * 1024
          ? '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB'
          : '${(fileSize / 1024).toStringAsFixed(0)} KB';

      if (!mounted) return;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (c) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            content: Row(
              children: [
                const Icon(Icons.insert_drive_file, size: 40, color: Colors.indigo),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(fileName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text(sizeStr, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                  ],
                )),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
              FilledButton.icon(onPressed: () => Navigator.pop(c, true), icon: const Icon(Icons.send, size: 16), label: const Text('إرسال')),
            ],
          ),
        ),
      );
      if (confirm != true) return;

      await _uploadAndSend(file, messageType: 5);
    } catch (e) {
      _showError('فشل إرسال الملف: $e');
    }
  }

  Future<void> _sendLocationMessage() async {
    try {
      final permission = await Geolocator.checkPermission();
      LocationPermission actualPermission = permission;
      if (permission == LocationPermission.denied) {
        actualPermission = await Geolocator.requestPermission();
        if (actualPermission == LocationPermission.denied ||
            actualPermission == LocationPermission.deniedForever) {
          _showError('تم رفض إذن الموقع');
          return;
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('جاري تحديد الموقع...')),
      );

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );

      if (!mounted) return;
      // تأكيد قبل الإرسال
      final confirm = await showDialog<bool>(
        context: context,
        builder: (c) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('إرسال الموقع'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.location_on, size: 48, color: Colors.red),
                const SizedBox(height: 8),
                const Text('هل تريد مشاركة موقعك الحالي؟'),
                const SizedBox(height: 4),
                Text('${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500])),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
              FilledButton.icon(
                onPressed: () => Navigator.pop(c, true),
                icon: const Icon(Icons.send, size: 16),
                label: const Text('إرسال'),
              ),
            ],
          ),
        ),
      );
      if (confirm != true) return;

      final locationJson = jsonEncode({'lat': position.latitude, 'lng': position.longitude});
      await ChatService.instance.sendMessage(
        roomId: widget.roomId,
        content: locationJson,
        messageType: 3,
      );
    } catch (e) {
      _showError('فشل إرسال الموقع: $e');
    }
  }

  Future<void> _sendContactMessage() async {
    // Show a simple dialog to enter contact info
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إرسال جهة اتصال', textDirection: TextDirection.rtl),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'الاسم'),
              textDirection: TextDirection.rtl,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: phoneCtrl,
              decoration: const InputDecoration(labelText: 'رقم الهاتف'),
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('إرسال')),
        ],
      ),
    );

    if (result != true) return;

    final name = nameCtrl.text.trim();
    final phone = phoneCtrl.text.trim();
    if (name.isEmpty || phone.isEmpty) return;

    try {
      await ChatService.instance.sendMessage(
        roomId: widget.roomId,
        content: '$name\n$phone',
        messageType: 4,
      );
    } catch (e) {
      _showError('فشل إرسال جهة الاتصال: $e');
    }
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopRecordingAndSend();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.audio);
      if (result == null || result.files.isEmpty) return;
      final path = result.files.first.path;
      if (path == null) return;
      await _uploadAndSend(File(path), messageType: 2);
    } catch (e) {
      _showError('فشل اختيار الملف الصوتي: $e');
    }
  }

  Future<void> _stopRecordingAndSend() async {
    if (mounted) setState(() => _isRecording = false);
  }

  Future<void> _uploadAndSend(File file, {required int messageType}) async {
    try {
      if (mounted) {
        setState(() {
          _isUploading = true;
          _uploadFileName = file.path.split('/').last.split('\\').last;
        });
      }

      final attachment =
          await ChatService.instance.uploadAttachment(widget.roomId, file);

      if (mounted) setState(() => _isUploading = false);

      if (attachment == null) {
        _showError('فشل رفع المرفق');
        return;
      }

      final filePath = attachment['filePath']?.toString() ??
          attachment['url']?.toString() ??
          '';
      if (filePath.isEmpty) {
        _showError('لم يتم الحصول على رابط المرفق');
        return;
      }

      await ChatService.instance.sendMessage(
        roomId: widget.roomId,
        content: filePath,
        messageType: messageType,
        replyToMessageId:
            _replyToMessage?['id']?.toString() ??
            _replyToMessage?['messageId']?.toString(),
      );

      if (mounted) setState(() => _replyToMessage = null);
    } catch (e) {
      if (mounted) setState(() => _isUploading = false);
      _showError('فشل الإرسال: $e');
    }
  }

  // ═══════════════════════════════════════
  // Typing
  // ═══════════════════════════════════════

  void _onTextChanged(String text) {
    // تحديث الزر (إرسال/ميكروفون)
    setState(() {});

    // Mention detection
    _detectMention(text);

    // Typing indicator
    if (text.isNotEmpty && !_iAmTyping) {
      _iAmTyping = true;
      ChatService.instance.startTyping(widget.roomId);
    }

    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(seconds: 3), _stopTyping);
  }

  void _stopTyping() {
    if (_iAmTyping) {
      _iAmTyping = false;
      ChatService.instance.stopTyping(widget.roomId);
    }
    _typingDebounce?.cancel();
  }

  void _detectMention(String text) {
    final pm = PermissionManager.instance;
    if (!pm.hasAction('chat.mention', 'send')) {
      if (_showMentionDropdown) {
        setState(() => _showMentionDropdown = false);
      }
      return;
    }

    // Find the last @ that might be an active mention
    final cursorPos = _textController.selection.baseOffset;
    if (cursorPos <= 0) {
      if (_showMentionDropdown) setState(() => _showMentionDropdown = false);
      return;
    }

    final textBeforeCursor = text.substring(0, cursorPos);
    final lastAt = textBeforeCursor.lastIndexOf('@');

    if (lastAt == -1 ||
        (lastAt > 0 && textBeforeCursor[lastAt - 1] != ' ')) {
      if (_showMentionDropdown) setState(() => _showMentionDropdown = false);
      return;
    }

    final query = textBeforeCursor.substring(lastAt + 1);
    if (query.contains(' ') && query.length > 20) {
      if (_showMentionDropdown) setState(() => _showMentionDropdown = false);
      return;
    }

    final filtered = _roomMembers.where((m) {
      final name = (m['fullName'] ?? m['userName'] ?? '').toString().toLowerCase();
      return name.contains(query.toLowerCase());
    }).toList();

    setState(() {
      _showMentionDropdown = filtered.isNotEmpty;
      _mentionQuery = query;
      _filteredMembers = filtered;
    });
  }

  void _insertMention(Map<String, dynamic> member) {
    final name = member['fullName']?.toString() ??
        member['userName']?.toString() ??
        '';
    final userId = member['userId']?.toString() ??
        member['id']?.toString() ??
        '';

    final text = _textController.text;
    final cursorPos = _textController.selection.baseOffset;
    final textBefore = text.substring(0, cursorPos);
    final lastAt = textBefore.lastIndexOf('@');

    if (lastAt == -1) return;

    final before = text.substring(0, lastAt);
    final after =
        cursorPos < text.length ? text.substring(cursorPos) : '';
    final newText = '$before@$name $after';

    _textController.text = newText;
    _textController.selection = TextSelection.collapsed(
      offset: lastAt + name.length + 2, // @name + space
    );

    _pendingMentions.add({'userId': userId, 'name': name});

    setState(() => _showMentionDropdown = false);
  }

  // ═══════════════════════════════════════
  // Audio Playback
  // ═══════════════════════════════════════

  AudioPlayer _getPlayer(String messageId) {
    return _audioPlayers.putIfAbsent(messageId, () => AudioPlayer());
  }

  Future<void> _playAudio(String messageId, String url) async {
    final player = _getPlayer(messageId);
    try {
      if (player.playing) {
        await player.pause();
      } else {
        if (player.duration == null) {
          await player.setUrl(url);
        }
        await player.play();
      }
      if (mounted) setState(() {});
    } catch (e) {
      _showError('فشل تشغيل الصوت');
    }
  }

  // ═══════════════════════════════════════
  // Message Actions
  // ═══════════════════════════════════════

  void _showMessageOptions(Map<String, dynamic> message) {
    final pm = PermissionManager.instance;
    final msgId = message['id']?.toString() ??
        message['messageId']?.toString() ??
        '';
    final content = message['content']?.toString() ?? '';
    final senderId = message['senderId']?.toString() ??
        message['senderUserId']?.toString() ??
        '';
    final canDelete = pm.hasAction('chat', 'delete') ||
        senderId == _currentUserId;

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // شريط Reactions السريع
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: ['👍', '❤️', '😂', '😮', '😢', '🙏'].map((emoji) =>
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(ctx);
                        _quickReact(message, emoji);
                      },
                      child: Text(emoji, style: const TextStyle(fontSize: 28)),
                    ),
                  ).toList(),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.reply),
                title: const Text('رد'),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _replyToMessage = message);
                  _textFocusNode.requestFocus();
                },
              ),
              if (message['messageType'] == 0 ||
                  message['messageType'] == null)
                ListTile(
                  leading: const Icon(Icons.copy),
                  title: const Text('نسخ'),
                  onTap: () {
                    Navigator.pop(ctx);
                    Clipboard.setData(ClipboardData(text: content));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تم النسخ')),
                    );
                  },
                ),
              ListTile(
                leading: const Icon(Icons.forward),
                title: const Text('إعادة توجيه'),
                onTap: () {
                  Navigator.pop(ctx);
                  _forwardMessage(message);
                },
              ),
              if (canDelete)
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text('حذف', style: TextStyle(color: Colors.red)),
                  onTap: () async {
                    Navigator.pop(ctx);

                    // هل المرسل وخلال 5 دقائق؟
                    final isMine = senderId == _currentUserId;
                    final createdAt = _parseDate(message['createdAt']?.toString());
                    final withinLimit = createdAt != null &&
                        DateTime.now().toUtc().difference(createdAt).inMinutes < 5;

                    String? deleteChoice;
                    if (isMine && withinLimit) {
                      deleteChoice = await showDialog<String>(
                        context: context,
                        builder: (c) => Directionality(
                          textDirection: TextDirection.rtl,
                          child: SimpleDialog(
                            title: const Text('حذف الرسالة'),
                            children: [
                              SimpleDialogOption(
                                onPressed: () => Navigator.pop(c, 'me'),
                                child: const Text('حذف لي فقط'),
                              ),
                              SimpleDialogOption(
                                onPressed: () => Navigator.pop(c, 'all'),
                                child: const Text('حذف للجميع', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        ),
                      );
                    } else {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: const Text('حذف الرسالة'),
                          content: const Text('هل أنت متأكد؟'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
                            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('حذف', style: TextStyle(color: Colors.red))),
                          ],
                        ),
                      );
                      if (confirm == true) deleteChoice = 'me';
                    }

                    if (deleteChoice == null) return;
                    final ok = await ChatService.instance.deleteMessage(msgId);
                    if (!ok && mounted) _showError('فشل حذف الرسالة');
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════
  // Search
  // ═══════════════════════════════════════

  void _showSearchBar() {
    setState(() {
      _isSearching = true;
      _searchMatchIndices.clear();
      _currentSearchMatch = -1;
      _searchQuery = '';
      _searchController.clear();
    });
  }

  void _closeSearch() {
    setState(() {
      _isSearching = false;
      _searchMatchIndices.clear();
      _currentSearchMatch = -1;
      _searchController.clear();
    });
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query.toLowerCase();
      _searchMatchIndices.clear();
      _currentSearchMatch = -1;

      if (_searchQuery.isEmpty) return;

      for (int i = 0; i < _messages.length; i++) {
        final content = (_messages[i]['content'] ?? '').toString().toLowerCase();
        if (content.contains(_searchQuery)) {
          _searchMatchIndices.add(i);
        }
      }

      if (_searchMatchIndices.isNotEmpty) {
        _currentSearchMatch = _searchMatchIndices.length - 1;
        _scrollToMessage(_searchMatchIndices[_currentSearchMatch]);
      }
    });
  }

  void _nextSearchMatch() {
    if (_searchMatchIndices.isEmpty) return;
    setState(() {
      _currentSearchMatch = (_currentSearchMatch + 1) % _searchMatchIndices.length;
      _scrollToMessage(_searchMatchIndices[_currentSearchMatch]);
    });
  }

  void _prevSearchMatch() {
    if (_searchMatchIndices.isEmpty) return;
    setState(() {
      _currentSearchMatch = (_currentSearchMatch - 1 + _searchMatchIndices.length) % _searchMatchIndices.length;
      _scrollToMessage(_searchMatchIndices[_currentSearchMatch]);
    });
  }

  void _scrollToMessage(int index) {
    // حساب الموقع التقريبي (كل رسالة ~80px)
    final offset = index * 80.0;
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        offset.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  /// إعادة توجيه رسالة لغرفة أخرى
  Future<void> _forwardMessage(Map<String, dynamic> message) async {
    // جلب قائمة الغرف
    final rooms = await ChatService.instance.getRooms();
    if (!mounted || rooms.isEmpty) return;

    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('إعادة توجيه إلى'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: ListView.builder(
              itemCount: rooms.length,
              itemBuilder: (_, i) {
                final r = rooms[i];
                if (r['id']?.toString() == widget.roomId) {
                  return const SizedBox.shrink();
                }
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.blue[100],
                    child: Icon(
                      r['type'] == 0
                          ? Icons.person
                          : r['type'] == 1
                              ? Icons.groups
                              : r['type'] == 2
                                  ? Icons.campaign
                                  : Icons.group,
                      size: 20,
                      color: Colors.blue[700],
                    ),
                  ),
                  title: Text(r['name']?.toString() ?? ''),
                  onTap: () => Navigator.pop(ctx, r),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
          ],
        ),
      ),
    );

    if (selected == null) return;

    final targetRoomId = selected['id']?.toString() ?? '';
    final content = message['content']?.toString() ?? '';
    final msgType = message['messageType'] ?? 0;

    await ChatService.instance.sendMessage(
      roomId: targetRoomId,
      content: content,
      messageType: msgType is int ? msgType : 0,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم إعادة التوجيه إلى ${selected['name'] ?? ''}')),
      );
    }
  }

  void _showError(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  // ═══════════════════════════════════════
  // Attachment Sheet
  // ═══════════════════════════════════════

  void _showAttachmentSheet() {
    final pm = PermissionManager.instance;
    final items = <_AttachItem>[];

    if (pm.hasAction('chat.send_image', 'send'))
      items.add(_AttachItem(Icons.photo_camera, 'صورة', Colors.pink, _sendImageMessage));
    if (pm.hasAction('chat.send_file', 'send'))
      items.add(_AttachItem(Icons.insert_drive_file, 'ملف', Colors.indigo, _sendFileMessage));
    if (pm.hasAction('chat.send_audio', 'send'))
      items.add(_AttachItem(Icons.headphones, 'صوت', Colors.orange, _toggleRecording));
    if (pm.hasAction('chat.send_location', 'send'))
      items.add(_AttachItem(Icons.location_on, 'موقع', Colors.green, _sendLocationMessage));
    if (pm.hasAction('chat.send_contact', 'send'))
      items.add(_AttachItem(Icons.person, 'جهة اتصال', Colors.blue, _sendContactMessage));

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 20,
              runSpacing: 16,
              children: items.map((item) => GestureDetector(
                onTap: () { Navigator.pop(ctx); item.onTap(); },
                child: SizedBox(
                  width: 65,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(radius: 26, backgroundColor: item.color, child: Icon(item.icon, color: Colors.white, size: 24)),
                      const SizedBox(height: 6),
                      Text(item.label, style: TextStyle(fontSize: 11, color: Colors.grey[700]), textAlign: TextAlign.center),
                    ],
                  ),
                ),
              )).toList(),
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════
  // Profile Card
  // ═══════════════════════════════════════

  /// فتح FTTH والبحث بالرقم أو الاسم
  void _searchInFtth({String? phone, String? name}) {
    final searchQuery = phone ?? name ?? '';
    if (searchQuery.isEmpty) return;

    final dual = DualAuthService.instance;
    final token = dual.ftthToken;

    if (token == null || token.isEmpty) {
      // FTTH غير مسجل — نسخ فقط
      Clipboard.setData(ClipboardData(text: searchQuery));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم نسخ "$searchQuery" — سجل دخول FTTH أولاً'), duration: const Duration(seconds: 3)),
        );
      }
      return;
    }

    // فتح صفحة البحث السريع مباشرة
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QuickSearchUsersPage(
          authToken: token,
          activatedBy: dual.ftthUsername ?? '',
          initialSearchQuery: searchQuery,
          hasServerSavePermission: false,
          hasWhatsAppPermission: false,
          isAdminFlag: dual.ftthIsAdmin,
          importantFtthApiPermissions: dual.ftthImportantPermissions.isNotEmpty
              ? dual.ftthImportantPermissions
              : null,
        ),
      ),
    );
  }

  /// تعديل اسم المجموعة
  Future<void> _editGroupName() async {
    final controller = TextEditingController(text: _displayRoomName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تعديل اسم المجموعة'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'اسم المجموعة',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            FilledButton(
              onPressed: () {
                final name = controller.text.trim();
                if (name.isNotEmpty) Navigator.pop(ctx, name);
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (newName == null || newName == _displayRoomName) return;

    final ok = await ChatService.instance.updateRoomName(widget.roomId, newName);
    if (ok && mounted) {
      setState(() => _editedRoomName = newName);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('فقط مدير المجموعة يمكنه تعديل الاسم')),
      );
    }
  }

  void _showProfileCard(String userId) {
    if (userId.isEmpty) return;
    EmployeeProfileCard.show(context, userId);
  }

  // ═══════════════════════════════════════
  // Members Dialog
  // ═══════════════════════════════════════

  void _showMembersDialog() {
    final pm = PermissionManager.instance;
    final canManage = pm.hasAction('chat.manage_members', 'add') ||
        pm.hasAction('chat.manage_members', 'delete');

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Row(
              children: [
                Expanded(child: Text('الاعضاء (${_roomMembers.length})')),
                if (canManage)
                  IconButton(
                    icon: const Icon(Icons.person_add, color: Colors.blue),
                    tooltip: 'إضافة أعضاء',
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _addMembersToRoom();
                    },
                  ),
                IconButton(
                  icon: Icon(Icons.exit_to_app, color: Colors.red[300], size: 20),
                  tooltip: 'مغادرة المجموعة',
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (c) => Directionality(
                        textDirection: TextDirection.rtl,
                        child: AlertDialog(
                          title: const Text('مغادرة المجموعة'),
                          content: const Text('هل تريد مغادرة هذه المجموعة؟'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
                            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('مغادرة', style: TextStyle(color: Colors.red))),
                          ],
                        ),
                      ),
                    );
                    if (confirm != true) return;
                    final ok = await ChatService.instance.leaveRoom(widget.roomId);
                    if (ok && mounted) Navigator.of(context).pop();
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: _roomMembers.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: _roomMembers.length,
                      itemBuilder: (_, i) {
                        final m = _roomMembers[i];
                        final name = m['fullName']?.toString() ?? m['userName']?.toString() ?? 'بدون اسم';
                        final id = m['userId']?.toString() ?? m['id']?.toString() ?? '';
                        final dept = m['department']?.toString() ?? '';
                        final isAdmin = m['isAdmin'] == true;
                        final isMe = id == _currentUserId;

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: _appBarColor,
                            child: Text(name.isNotEmpty ? name[0] : '?', style: const TextStyle(color: Colors.white)),
                          ),
                          title: Row(
                            children: [
                              Text(name),
                              if (isAdmin) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                                  child: const Text('مدير', style: TextStyle(fontSize: 10, color: Colors.blue)),
                                ),
                              ],
                              if (isMe) ...[
                                const SizedBox(width: 6),
                                const Text('(أنت)', style: TextStyle(fontSize: 11, color: Colors.grey)),
                              ],
                            ],
                          ),
                          subtitle: dept.isNotEmpty ? Text(dept, style: TextStyle(fontSize: 12, color: Colors.grey[500])) : null,
                          trailing: canManage && !isMe && !isAdmin
                              ? IconButton(
                                  icon: Icon(Icons.remove_circle_outline, color: Colors.red[300], size: 20),
                                  tooltip: 'إزالة',
                                  onPressed: () async {
                                    final confirm = await showDialog<bool>(
                                      context: ctx,
                                      builder: (c) => AlertDialog(
                                        title: const Text('إزالة عضو'),
                                        content: Text('هل تريد إزالة $name من المجموعة؟'),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
                                          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('إزالة', style: TextStyle(color: Colors.red))),
                                        ],
                                      ),
                                    );
                                    if (confirm != true) return;
                                    await ChatService.instance.removeMember(widget.roomId, id);
                                    await _loadMembers();
                                    setDialogState(() {});
                                    if (mounted) setState(() {});
                                  },
                                )
                              : null,
                          onTap: () {
                            Navigator.pop(ctx);
                            _showProfileCard(id);
                          },
                        );
                      },
                    ),
            ),
          );
        }),
      ),
    );
  }

  /// إضافة أعضاء جدد للغرفة
  Future<void> _addMembersToRoom() async {
    final available = await ChatService.instance.getAvailableUsers();
    if (!mounted || available.isEmpty) return;

    final currentIds = _roomMembers.map((m) => m['userId']?.toString() ?? m['id']?.toString()).toSet();
    final allUsers = available.where((u) => !currentIds.contains(u['userId']?.toString())).toList();

    if (allUsers.isEmpty) {
      _showError('جميع الموظفين موجودون بالفعل');
      return;
    }

    // جمع الأقسام والأدوار المتاحة
    final departments = <String>{'الكل'};
    final roles = <String>{'الكل'};
    for (final u in allUsers) {
      final dept = u['department']?.toString() ?? '';
      if (dept.isNotEmpty) departments.add(dept);
      final role = u['role'];
      if (role != null) {
        roles.add(role is int ? _getRoleLabel(role) : role.toString());
      }
    }

    final selectedIds = <String>{};
    String searchQuery = '';
    String selectedDept = 'الكل';
    String selectedRole = 'الكل';
    final searchCtrl = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(builder: (ctx, ss) {
          // تصفية
          final filtered = allUsers.where((u) {
            final name = u['fullName']?.toString() ?? '';
            final dept = u['department']?.toString() ?? '';
            final role = u['role'];
            final roleLabel = role is int ? _getRoleLabel(role) : role?.toString() ?? '';

            if (searchQuery.isNotEmpty && !name.contains(searchQuery)) return false;
            if (selectedDept != 'الكل' && dept != selectedDept) return false;
            if (selectedRole != 'الكل' && roleLabel != selectedRole) return false;
            return true;
          }).toList();

          return AlertDialog(
            titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            contentPadding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            title: const Text('إضافة أعضاء', style: TextStyle(fontSize: 16)),
            content: SizedBox(
              width: double.maxFinite,
              height: MediaQuery.of(ctx).size.height * 0.6,
              child: Column(
                children: [
                  // بحث
                  SizedBox(
                    height: 38,
                    child: TextField(
                      controller: searchCtrl,
                      textDirection: TextDirection.rtl,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'بحث بالاسم...',
                        hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]),
                        prefixIcon: Icon(Icons.search, size: 20, color: Colors.grey[400]),
                        filled: true, fillColor: Colors.grey[100],
                        contentPadding: EdgeInsets.zero,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                      ),
                      onChanged: (v) => ss(() => searchQuery = v),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // فلاتر
                  Row(
                    children: [
                      // فلتر القسم
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: selectedDept,
                          isExpanded: true,
                          isDense: true,
                          style: const TextStyle(fontSize: 12, color: Colors.black87),
                          decoration: InputDecoration(
                            labelText: 'القسم',
                            labelStyle: const TextStyle(fontSize: 11),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          items: departments.map((d) => DropdownMenuItem(value: d, child: Text(d, style: const TextStyle(fontSize: 12)))).toList(),
                          onChanged: (v) => ss(() => selectedDept = v ?? 'الكل'),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // فلتر الدور
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: selectedRole,
                          isExpanded: true,
                          isDense: true,
                          style: const TextStyle(fontSize: 12, color: Colors.black87),
                          decoration: InputDecoration(
                            labelText: 'الدور',
                            labelStyle: const TextStyle(fontSize: 11),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          items: roles.map((r) => DropdownMenuItem(value: r, child: Text(r, style: const TextStyle(fontSize: 12)))).toList(),
                          onChanged: (v) => ss(() => selectedRole = v ?? 'الكل'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // تحديد الكل / إلغاء الكل
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () => ss(() {
                          for (final u in filtered) {
                            selectedIds.add(u['userId']?.toString() ?? u['id']?.toString() ?? '');
                          }
                        }),
                        icon: const Icon(Icons.select_all, size: 16),
                        label: const Text('تحديد الكل', style: TextStyle(fontSize: 11)),
                        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                      ),
                      TextButton.icon(
                        onPressed: () => ss(() => selectedIds.clear()),
                        icon: const Icon(Icons.deselect, size: 16),
                        label: const Text('إلغاء الكل', style: TextStyle(fontSize: 11)),
                        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                      ),
                      const Spacer(),
                      Text('${selectedIds.length} محدد', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                    ],
                  ),
                  Divider(height: 1, color: Colors.grey[200]),
                  // القائمة
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(child: Text('لا توجد نتائج', style: TextStyle(color: Colors.grey[400])))
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (_, i) {
                              final u = filtered[i];
                              final id = u['userId']?.toString() ?? u['id']?.toString() ?? '';
                              final name = u['fullName']?.toString() ?? '';
                              final dept = u['department']?.toString() ?? '';
                              return CheckboxListTile(
                                dense: true,
                                value: selectedIds.contains(id),
                                title: Text(name, style: const TextStyle(fontSize: 13)),
                                subtitle: dept.isNotEmpty ? Text(dept, style: TextStyle(fontSize: 11, color: Colors.grey[500])) : null,
                                onChanged: (_) => ss(() {
                                  if (selectedIds.contains(id)) { selectedIds.remove(id); } else { selectedIds.add(id); }
                                }),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
              FilledButton(
                onPressed: selectedIds.isEmpty ? null : () => Navigator.pop(ctx, true),
                child: Text('إضافة (${selectedIds.length})'),
              ),
            ],
          );
        }),
      ),
    );

    searchCtrl.dispose();
    if (result != true || selectedIds.isEmpty) return;

    await ChatService.instance.addMembers(widget.roomId, selectedIds.toList());
    await _loadMembers();
    if (mounted) setState(() {});
    _showError('تم إضافة ${selectedIds.length} عضو');
  }

  String _getRoleLabel(int role) => switch (role) {
    0 => 'مواطن', 10 => 'موظف', 12 => 'فني', 13 => 'قائد فني',
    14 => 'مشرف', 20 => 'مدير شركة', 90 => 'مسؤول', 100 => 'مسؤول أعلى',
    _ => 'موظف',
  };

  // ═══════════════════════════════════════
  // Image Full Screen
  // ═══════════════════════════════════════

  void _showFullScreenImage(String url) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: Center(
            child: InteractiveViewer(
              child: Image.network(
                url,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.broken_image,
                  size: 64,
                  color: Colors.white54,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════
  // Helpers
  // ═══════════════════════════════════════

  String _formatTime(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '';
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      return intl.DateFormat('HH:mm').format(dt);
    } catch (_) {
      return '';
    }
  }

  bool _isSentByMe(Map<String, dynamic> msg) {
    final senderId = msg['senderId']?.toString() ??
        msg['senderUserId']?.toString() ??
        '';
    return senderId == _currentUserId;
  }

  String _senderName(Map<String, dynamic> msg) {
    return msg['senderName']?.toString() ??
        msg['senderFullName']?.toString() ??
        '';
  }

  String _getMessageId(Map<String, dynamic> msg) {
    return msg['id']?.toString() ?? msg['messageId']?.toString() ?? '';
  }

  int _getMessageType(Map<String, dynamic> msg) {
    final t = msg['messageType'];
    if (t is int) return t;
    if (t is String) return int.tryParse(t) ?? 0;
    return 0;
  }

  // ═══ Date helpers ═══

  DateTime? _parseDate(String? s) {
    if (s == null || s.isEmpty) return null;
    try {
      return DateTime.parse(s).toLocal();
    } catch (_) {
      return null;
    }
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _formatDateLabel(DateTime dt) {
    final now = DateTime.now();
    if (_isSameDay(dt, now)) return 'اليوم';
    if (_isSameDay(dt, now.subtract(const Duration(days: 1)))) return 'أمس';
    return intl.DateFormat('yyyy/MM/dd').format(dt);
  }

  Widget _buildDateSeparator(DateTime date) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4)],
        ),
        child: Text(
          _formatDateLabel(date),
          style: TextStyle(fontSize: 12, color: Colors.grey[700], fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _bgColor,
        appBar: _buildAppBar(),
        body: Column(
          children: [
            if (_isSearching) _buildSearchBar(),
            // مؤشر الاتصال
            if (!ChatService.instance.isConnected)
              Container(
                width: double.infinity,
                color: Colors.red[50],
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.wifi_off, size: 13, color: Colors.red[400]),
                    const SizedBox(width: 4),
                    Text('غير متصل — الرسائل تتحدث كل 5 ثوانٍ', style: TextStyle(fontSize: 10, color: Colors.red[400])),
                  ],
                ),
              ),
            Expanded(
              child: Stack(
                children: [
                  _buildMessageList(),
                  // زر العودة للأسفل
                  if (_showScrollToBottom)
                    Positioned(
                      bottom: 12,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: GestureDetector(
                          onTap: () {
                            _scrollToBottom();
                            setState(() {
                              _showScrollToBottom = false;
                              _newMessagesSinceScrolled = 0;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8, offset: const Offset(0, 2))],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_newMessagesSinceScrolled > 0) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(10)),
                                    child: Text('$_newMessagesSinceScrolled', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                const Icon(Icons.keyboard_arrow_down, size: 20, color: Color(0xFF075E54)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (_isUploading) _buildUploadIndicator(),
            if (_replyToMessage != null) _buildReplyPreview(),
            if (_showMentionDropdown) _buildMentionDropdown(),
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  // ─── AppBar ───

  Widget _buildSearchBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: _closeSearch,
          ),
          Expanded(
            child: TextField(
              controller: _searchController,
              autofocus: true,
              textDirection: TextDirection.rtl,
              decoration: const InputDecoration(
                hintText: 'بحث في الرسائل...',
                hintTextDirection: TextDirection.rtl,
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
              onChanged: _onSearchChanged,
            ),
          ),
          if (_searchMatchIndices.isNotEmpty) ...[
            Text(
              '${_currentSearchMatch + 1}/${_searchMatchIndices.length}',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_up, size: 20),
              onPressed: _prevSearchMatch,
            ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_down, size: 20),
              onPressed: _nextSearchMatch,
            ),
          ],
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final isGroup = widget.roomType == 1 ||
        widget.roomType == 2 ||
        widget.roomType == 3;

    String subtitle = '';
    if (_typingUsers.isNotEmpty) {
      final names = _typingUsers.values.toList();
      if (names.length == 1) {
        subtitle = '${names.first} يكتب...';
      } else {
        subtitle = '${names.length} يكتبون...';
      }
    } else if (widget.roomType == 0 && _isOtherUserOnline) {
      subtitle = 'متصل الآن';
    } else if (isGroup) {
      subtitle = '${_roomMembers.length} عضو';
    }

    final isMobile = MediaQuery.of(context).size.width < 600;
    final isDesktopSplit = !isMobile && MediaQuery.of(context).size.width > 768;
    return AppBar(
      backgroundColor: _appBarColor,
      foregroundColor: Colors.white,
      toolbarHeight: isMobile ? 48 : 56,
      automaticallyImplyLeading: !isDesktopSplit,
      title: GestureDetector(
        onTap: isGroup ? _editGroupName : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    _displayRoomName,
                    style: TextStyle(fontSize: isMobile ? 15 : 17, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isGroup) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.edit, size: isMobile ? 12 : 14, color: Colors.white54),
                ],
              ],
            ),
            if (subtitle.isNotEmpty)
              Text(
                subtitle,
                style: TextStyle(fontSize: isMobile ? 11 : 12, fontStyle: FontStyle.italic, color: Colors.white70),
              ),
          ],
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.search),
          tooltip: 'بحث',
          onPressed: _showSearchBar,
        ),
        if (isGroup)
          IconButton(
            icon: const Icon(Icons.group),
            tooltip: 'الاعضاء',
            onPressed: _showMembersDialog,
          ),
      ],
    );
  }

  // ─── Message List ───

  Widget _buildMessageList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text('لا توجد رسائل بعد', style: TextStyle(color: Colors.grey[500], fontSize: 16, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Text('أرسل رسالة لبدء المحادثة 👋', style: TextStyle(color: Colors.grey[400], fontSize: 13)),
          ],
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollStartNotification) {
          FocusScope.of(context).unfocus();
        }
        return false;
      },
      child: ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: false,
      itemCount: _messages.length + (_isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (_isLoadingMore && index == _messages.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final msg = _messages[index];
        // هل الرسالة التالية (الأقدم) من نفس المرسل؟ (reversed list)
        final prevMsg = index < _messages.length - 1 ? _messages[index + 1] : null;
        final nextMsg = index > 0 ? _messages[index - 1] : null;
        final currSender = msg['senderId']?.toString() ?? '';
        final prevSender = prevMsg?['senderId']?.toString() ?? '';
        final nextSender = nextMsg?['senderId']?.toString() ?? '';
        final isFirstInGroup = currSender != prevSender;
        final isLastInGroup = currSender != nextSender;

        final isHighlighted = _isSearching &&
            _searchMatchIndices.isNotEmpty &&
            _currentSearchMatch >= 0 &&
            _currentSearchMatch < _searchMatchIndices.length &&
            _searchMatchIndices[_currentSearchMatch] == index;

        // فاصل التاريخ (reversed: نقارن مع الرسالة التالية في القائمة = الأقدم)
        Widget? dateSeparator;
        if (index < _messages.length - 1) {
          final nextMsg = _messages[index + 1];
          final currDate = _parseDate(msg['createdAt']?.toString() ?? msg['sentAt']?.toString());
          final nextDate = _parseDate(nextMsg['createdAt']?.toString() ?? nextMsg['sentAt']?.toString());
          if (currDate != null && nextDate != null && !_isSameDay(currDate, nextDate)) {
            dateSeparator = _buildDateSeparator(currDate);
          }
        } else if (index == _messages.length - 1) {
          // أول رسالة (الأقدم) — عرض فاصل التاريخ
          final currDate = _parseDate(msg['createdAt']?.toString() ?? msg['sentAt']?.toString());
          if (currDate != null) {
            dateSeparator = _buildDateSeparator(currDate);
          }
        }

        return RepaintBoundary(
          child: Column(
            children: [
              if (dateSeparator != null) dateSeparator,
              Container(
                color: isHighlighted ? Colors.yellow.withValues(alpha: 0.3) : null,
                child: _buildMessageBubble(msg, isFirstInGroup: isFirstInGroup, isLastInGroup: isLastInGroup),
              ),
            ],
          ),
        );
      },
    ),
    );
  }

  // ─── Message Bubble ───

  Widget _buildMessageBubble(Map<String, dynamic> msg, {bool isFirstInGroup = true, bool isLastInGroup = true}) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final isSent = _isSentByMe(msg);
    final msgType = _getMessageType(msg);
    final content = msg['content']?.toString() ?? '';
    final time = _formatTime(
        msg['createdAt']?.toString() ?? msg['sentAt']?.toString());
    final senderName = _senderName(msg);
    final senderId = msg['senderId']?.toString() ??
        msg['senderUserId']?.toString() ??
        '';
    final isRead = msg['isRead'] == true || msg['readAt'] != null;
    final isForwarded = msg['isForwarded'] == true;
    final replyTo = msg['replyTo'] as Map<String, dynamic>? ??
        msg['replyToMessage'] as Map<String, dynamic>?;
    final isGroup = widget.roomType != 0;

    final showAvatar = !isSent && isLastInGroup;
    final showName = isGroup && !isSent && isFirstInGroup && senderName.isNotEmpty;
    final verticalMargin = isLastInGroup ? (isMobile ? 6.0 : 8.0) : 1.0;

    return Padding(
      padding: EdgeInsets.only(bottom: verticalMargin),
      child: Align(
      alignment: isSent ? Alignment.centerLeft : Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // أفاتار — فقط لآخر رسالة في المجموعة
          if (!isSent) ...[
            if (showAvatar)
              GestureDetector(
                onTap: () => _showProfileCard(senderId),
                child: CircleAvatar(
                  radius: isMobile ? 13 : 15,
                  backgroundColor: _getSenderColor(senderId),
                  child: Text(
                    senderName.isNotEmpty ? senderName[0] : '?',
                    style: TextStyle(color: Colors.white, fontSize: isMobile ? 11 : 13, fontWeight: FontWeight.bold),
                  ),
                ),
              )
            else
              SizedBox(width: isMobile ? 26 : 30),
            const SizedBox(width: 4),
          ],

          // Bubble
          Flexible(
            child: GestureDetector(
              onLongPress: () {
                HapticFeedback.mediumImpact();
                _showMessageOptions(msg);
              },
              onDoubleTap: () => _quickReact(msg, '👍'),
              child: Column(
                crossAxisAlignment: isSent ? CrossAxisAlignment.start : CrossAxisAlignment.end,
                children: [
              Container(
                padding:
                    EdgeInsets.symmetric(horizontal: isMobile ? 8 : 12, vertical: isMobile ? 5 : 7),
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width *
                      (MediaQuery.of(context).size.width > 600 ? 0.6 : 0.78),
                ),
                decoration: BoxDecoration(
                  color: isSent ? _bubbleSentColor : _bubbleReceivedColor,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(12),
                    topRight: const Radius.circular(12),
                    bottomLeft:
                        isSent ? const Radius.circular(12) : Radius.zero,
                    bottomRight:
                        isSent ? Radius.zero : const Radius.circular(12),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Forwarded label
                    if (isForwarded)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '\u21A9\uFE0F رسالة محولة',
                          style: TextStyle(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            color: isSent
                                ? Colors.white70
                                : Colors.grey.shade600,
                          ),
                        ),
                      ),

                    // اسم المرسل — فقط أول رسالة في المجموعة
                    if (showName)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          senderName,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _getSenderColor(senderId),
                          ),
                        ),
                      ),

                    // Reply preview
                    if (replyTo != null) _buildInlineReplyPreview(replyTo, isSent),

                    // محتوى + وقت
                    _buildContentWithTime(msg, msgType, content, isSent, time, isRead),
                  ],
                ),
              ),
              // زر إعادة إرسال عند الفشل
              if (msg['_status'] == 'failed')
                GestureDetector(
                  onTap: () => _retryMessage(msg),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.refresh, size: 14, color: Colors.red[400]),
                        const SizedBox(width: 4),
                        Text('إعادة الإرسال', style: TextStyle(fontSize: 11, color: Colors.red[400])),
                      ],
                    ),
                  ),
                ),
              // Reactions row
              if ((msg['reactions'] as List?)?.isNotEmpty == true)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Wrap(
                    spacing: 4,
                    children: _buildReactionChips(msg),
                  ),
                ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
    );
  }

  List<Widget> _buildReactionChips(Map<String, dynamic> msg) {
    final reactions = msg['reactions'] as List? ?? [];
    final grouped = <String, int>{};
    for (final r in reactions) {
      final emoji = (r is Map ? r['emoji'] : r.toString()) ?? '';
      if (emoji.isNotEmpty) grouped[emoji] = (grouped[emoji] ?? 0) + 1;
    }
    return grouped.entries.map((e) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text('${e.key} ${e.value > 1 ? e.value : ''}',
          style: const TextStyle(fontSize: 13)),
    )).toList();
  }

  /// إعادة إرسال رسالة فاشلة
  Future<void> _retryMessage(Map<String, dynamic> msg) async {
    final content = msg['_retryContent']?.toString() ?? msg['content']?.toString() ?? '';
    final replyId = msg['_retryReplyId']?.toString();
    final mentions = (msg['_retryMentions'] as List?)?.cast<String>();
    final tempId = msg['id']?.toString();

    if (content.isEmpty) return;

    // وسم كـ "يرسل"
    if (mounted) setState(() => msg.remove('_status'));

    try {
      await ChatService.instance.sendMessage(
        roomId: widget.roomId,
        content: content,
        messageType: 0,
        replyToMessageId: replyId,
        mentionUserIds: mentions,
      );
    } catch (e) {
      if (mounted) setState(() => msg['_status'] = 'failed');
    }
  }

  Future<void> _quickReact(Map<String, dynamic> msg, String emoji) async {
    final msgId = msg['id']?.toString() ?? msg['messageId']?.toString();
    if (msgId == null) return;
    await ChatService.instance.toggleReaction(msgId, emoji);
    // تحديث محلي
    if (mounted) {
      setState(() {
        final reactions = (msg['reactions'] as List?) ?? [];
        final myId = _currentUserId;
        final existing = reactions.indexWhere((r) =>
            r is Map && r['userId']?.toString() == myId && r['emoji'] == emoji);
        if (existing >= 0) {
          reactions.removeAt(existing);
        } else {
          reactions.add({'emoji': emoji, 'userId': myId});
        }
        msg['reactions'] = reactions;
      });
    }
  }

  // ─── Message Content by Type ───

  Widget _buildTimeAndStatus(String time, bool isSent, bool isRead, Map<String, dynamic> msg) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(time, style: TextStyle(fontSize: 9, color: isSent ? Colors.white60 : Colors.grey.shade500)),
        if (isSent) ...[
          const SizedBox(width: 3),
          if (msg['_status'] == 'failed')
            const Icon(Icons.error_outline, size: 12, color: Colors.redAccent)
          else if ((msg['id']?.toString() ?? '').startsWith('temp_'))
            const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white60))
          else
            Icon(isRead ? Icons.done_all : Icons.done, size: 13, color: isRead ? Colors.lightBlueAccent : Colors.white60),
        ],
      ],
    );
  }

  Widget _buildContentWithTime(Map<String, dynamic> msg, int msgType, String content, bool isSent, String time, bool isRead) {
    if (msgType == 0 && content.length < 35) {
      // نص قصير: محتوى + وقت في نفس السطر
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Flexible(child: _buildMessageContent(msg, msgType, content, isSent)),
          const SizedBox(width: 6),
          _buildTimeAndStatus(time, isSent, isRead, msg),
        ],
      );
    }
    // نص طويل أو مرفق: وقت تحت المحتوى
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildMessageContent(msg, msgType, content, isSent),
        const SizedBox(height: 2),
        Align(
          alignment: isSent ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
          child: _buildTimeAndStatus(time, isSent, isRead, msg),
        ),
      ],
    );
  }

  Widget _buildMessageContent(
    Map<String, dynamic> msg,
    int msgType,
    String content,
    bool isSent,
  ) {
    final textColor = isSent ? Colors.white : Colors.black87;

    switch (msgType) {
      case 1: // Image
        return InkWell(
          onTap: () => _showFullScreenImage(content),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              content,
              width: 200,
              height: 200,
              fit: BoxFit.cover,
              loadingBuilder: (_, child, progress) {
                if (progress == null) return child;
                return SizedBox(
                  width: 200,
                  height: 200,
                  child: Center(
                    child: CircularProgressIndicator(
                      value: progress.expectedTotalBytes != null
                          ? progress.cumulativeBytesLoaded /
                              progress.expectedTotalBytes!
                          : null,
                    ),
                  ),
                );
              },
              errorBuilder: (_, __, ___) => Container(
                width: 200,
                height: 120,
                color: Colors.grey.shade300,
                child: const Icon(Icons.broken_image, size: 40),
              ),
            ),
          ),
        );

      case 2: // Audio
        return _buildAudioPlayer(msg, content, isSent);

      case 3: // Location
        String? lat, lng;
        try {
          final loc = jsonDecode(content);
          lat = loc['lat']?.toString();
          lng = loc['lng']?.toString();
        } catch (_) {
          final parts = content.split(',');
          if (parts.length == 2) { lat = parts[0].trim(); lng = parts[1].trim(); }
        }
        final mapUrl = lat != null && lng != null ? 'https://www.google.com/maps/search/?api=1&query=$lat,$lng' : null;
        return InkWell(
          onTap: mapUrl != null ? () async {
            final uri = Uri.parse(mapUrl);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            } else {
              Clipboard.setData(ClipboardData(text: mapUrl));
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ رابط الموقع')));
            }
          } : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.location_on, color: Colors.red.shade400, size: 20),
              const SizedBox(width: 6),
              Text('موقع مشترك', style: TextStyle(color: textColor, fontSize: 13)),
              if (mapUrl != null) ...[
                const SizedBox(width: 6),
                Icon(Icons.open_in_new, size: 13, color: isSent ? Colors.white54 : Colors.blue.shade300),
              ],
            ],
          ),
        );

      case 4: // Contact
        String contactName = '', contactPhone = '';
        try {
          final c = jsonDecode(content);
          contactName = c['name']?.toString() ?? '';
          contactPhone = c['phone']?.toString() ?? '';
        } catch (_) {
          final lines = content.split('\n');
          contactName = lines.isNotEmpty ? lines[0] : '';
          contactPhone = lines.length > 1 ? lines[1] : '';
        }
        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isSent ? Colors.blue.shade700 : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.person, color: isSent ? Colors.white : Colors.orange, size: 24),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(contactName, style: TextStyle(fontWeight: FontWeight.bold, color: textColor, fontSize: 14)),
                        if (contactPhone.isNotEmpty)
                          Text(contactPhone, style: TextStyle(fontSize: 12, color: isSent ? Colors.white70 : Colors.grey.shade600), textDirection: TextDirection.ltr),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (contactPhone.isNotEmpty)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _searchInFtth(phone: contactPhone),
                        icon: Icon(Icons.search, size: 14, color: isSent ? Colors.white70 : Colors.blue),
                        label: Text('بحث بالرقم', style: TextStyle(fontSize: 11, color: isSent ? Colors.white : Colors.blue)),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: isSent ? Colors.white30 : Colors.blue.shade200),
                          padding: const EdgeInsets.symmetric(vertical: 4),
                        ),
                      ),
                    ),
                  if (contactPhone.isNotEmpty && contactName.isNotEmpty) const SizedBox(width: 6),
                  if (contactName.isNotEmpty)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _searchInFtth(name: contactName),
                        icon: Icon(Icons.person_search, size: 14, color: isSent ? Colors.white70 : Colors.teal),
                        label: Text('بحث بالاسم', style: TextStyle(fontSize: 11, color: isSent ? Colors.white : Colors.teal)),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: isSent ? Colors.white30 : Colors.teal.shade200),
                          padding: const EdgeInsets.symmetric(vertical: 4),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );

      case 5: // File
        final fileName = content.split('/').last;
        return InkWell(
          onTap: () {
            Clipboard.setData(ClipboardData(text: content));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('تم نسخ رابط الملف')),
            );
          },
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isSent
                  ? Colors.blue.shade700
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.insert_drive_file,
                    color: isSent ? Colors.white : Colors.purple, size: 28),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    fileName,
                    style: TextStyle(
                      color: textColor,
                      decoration: TextDecoration.underline,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );

      default: // Text (0) — نص قابل للنسخ
        return _buildSelectableFormattedText(content, textColor);
    }
  }

  /// عرض نص منسّق: *غامق* _مائل_ ~مشطوب~ `كود`
  Widget _buildFormattedText(String text, Color color) {
    final spans = <InlineSpan>[];
    // regex لاكتشاف التنسيق
    final regex = RegExp(r'\*(.+?)\*|_(.+?)_|~(.+?)~|`(.+?)`');
    int lastEnd = 0;

    for (final match in regex.allMatches(text)) {
      // نص عادي قبل المطابقة
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start), style: TextStyle(fontSize: 14, color: color)));
      }
      if (match.group(1) != null) {
        // *غامق*
        spans.add(TextSpan(text: match.group(1), style: TextStyle(fontSize: 14, color: color, fontWeight: FontWeight.bold)));
      } else if (match.group(2) != null) {
        // _مائل_
        spans.add(TextSpan(text: match.group(2), style: TextStyle(fontSize: 14, color: color, fontStyle: FontStyle.italic)));
      } else if (match.group(3) != null) {
        // ~مشطوب~
        spans.add(TextSpan(text: match.group(3), style: TextStyle(fontSize: 14, color: color, decoration: TextDecoration.lineThrough)));
      } else if (match.group(4) != null) {
        // `كود`
        spans.add(WidgetSpan(child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
          child: Text(match.group(4)!, style: TextStyle(fontSize: 13, color: color, fontFamily: 'monospace')),
        )));
      }
      lastEnd = match.end;
    }

    // نص متبقي
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd), style: TextStyle(fontSize: 14, color: color)));
    }

    if (spans.isEmpty) {
      return Text(text, style: TextStyle(fontSize: 14, color: color));
    }
    return RichText(text: TextSpan(children: spans));
  }

  /// نص قابل للتحديد والنسخ مع تنسيق
  Widget _buildSelectableFormattedText(String text, Color color) {
    // كشف أرقام الهاتف (07xxxxxxxxx أو رقم 10+ أرقام)
    final phoneRegex = RegExp(r'(07\d{9}|\d{10,})');
    final phoneMatch = phoneRegex.firstMatch(text);

    // بدون تنسيق — SelectableText مع كشف أرقام
    if (!text.contains('*') && !text.contains('_') && !text.contains('~') && !text.contains('`')) {
      if (phoneMatch != null) {
        // النص يحتوي رقم هاتف — اجعله قابل للضغط
        final before = text.substring(0, phoneMatch.start);
        final phone = phoneMatch.group(0)!;
        final after = text.substring(phoneMatch.end);
        return SelectableText.rich(TextSpan(
          style: TextStyle(fontSize: 14, color: color),
          children: [
            if (before.isNotEmpty) TextSpan(text: before),
            TextSpan(
              text: phone,
              style: TextStyle(color: color, decoration: TextDecoration.underline, fontWeight: FontWeight.w600),
              recognizer: TapGestureRecognizer()..onTap = () => _searchInFtth(phone: phone),
            ),
            if (after.isNotEmpty) TextSpan(text: after),
          ],
        ));
      }
      return SelectableText(text, style: TextStyle(fontSize: 14, color: color));
    }

    // مع تنسيق — نبني TextSpans فقط (بدون WidgetSpan لأن SelectableText لا يدعمها)
    final spans = <TextSpan>[];
    final regex = RegExp(r'\*(.+?)\*|_(.+?)_|~(.+?)~|`(.+?)`');
    int lastEnd = 0;

    for (final match in regex.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }
      if (match.group(1) != null) {
        spans.add(TextSpan(text: match.group(1), style: const TextStyle(fontWeight: FontWeight.bold)));
      } else if (match.group(2) != null) {
        spans.add(TextSpan(text: match.group(2), style: const TextStyle(fontStyle: FontStyle.italic)));
      } else if (match.group(3) != null) {
        spans.add(TextSpan(text: match.group(3), style: const TextStyle(decoration: TextDecoration.lineThrough)));
      } else if (match.group(4) != null) {
        spans.add(TextSpan(text: match.group(4), style: const TextStyle(fontFamily: 'monospace', backgroundColor: Color(0x22000000))));
      }
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }

    return SelectableText.rich(
      TextSpan(children: spans, style: TextStyle(fontSize: 14, color: color)),
    );
  }

  // ─── Audio Player Widget ───

  Widget _buildAudioPlayer(
      Map<String, dynamic> msg, String url, bool isSent) {
    final msgId = _getMessageId(msg);
    final player = _getPlayer(msgId);
    final textColor = isSent ? Colors.white : Colors.black87;

    return StreamBuilder<PlayerState>(
      stream: player.playerStateStream,
      builder: (context, snapshot) {
        final state = snapshot.data;
        final isPlaying = state?.playing ?? false;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: () => _playAudio(msgId, url),
              child: Icon(
                isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                size: 36,
                color: isSent ? Colors.white : _bubbleSentColor,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: StreamBuilder<Duration>(
                stream: player.positionStream,
                builder: (context, posSnap) {
                  final position = posSnap.data ?? Duration.zero;
                  final duration = player.duration ?? Duration.zero;
                  final progress = duration.inMilliseconds > 0
                      ? position.inMilliseconds / duration.inMilliseconds
                      : 0.0;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 4,
                        child: LinearProgressIndicator(
                          value: progress.clamp(0.0, 1.0),
                          backgroundColor: isSent
                              ? Colors.white24
                              : Colors.grey.shade300,
                          valueColor: AlwaysStoppedAnimation(
                            isSent ? Colors.white : _bubbleSentColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatDuration(
                            isPlaying ? position : duration),
                        style: TextStyle(
                          fontSize: 11,
                          color: isSent
                              ? Colors.white70
                              : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ─── Inline Reply Preview (inside bubble) ───

  Widget _buildInlineReplyPreview(
      Map<String, dynamic> reply, bool isSent) {
    final replyContent = reply['content']?.toString() ?? '';
    final replySender = reply['senderName']?.toString() ??
        reply['senderFullName']?.toString() ??
        '';

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: isSent
            ? Colors.blue.shade800.withOpacity(0.5)
            : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(6),
        border: Border(
          right: BorderSide(
            color: isSent ? Colors.white54 : _bubbleSentColor,
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (replySender.isNotEmpty)
            Text(
              replySender,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isSent ? Colors.white70 : _bubbleSentColor,
              ),
            ),
          Text(
            replyContent.length > 80
                ? '${replyContent.substring(0, 80)}...'
                : replyContent,
            style: TextStyle(
              fontSize: 12,
              color: isSent ? Colors.white60 : Colors.grey.shade700,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ─── Reply Preview Bar (above input) ───

  Widget _buildReplyPreview() {
    final msg = _replyToMessage!;
    final sender = _senderName(msg);
    final content = msg['content']?.toString() ?? '';

    return Container(
      color: Colors.grey.shade200,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 40,
            decoration: BoxDecoration(
              color: _bubbleSentColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (sender.isNotEmpty)
                  Text(
                    sender,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: _bubbleSentColor,
                    ),
                  ),
                Text(
                  content.length > 60
                      ? '${content.substring(0, 60)}...'
                      : content,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => setState(() => _replyToMessage = null),
          ),
        ],
      ),
    );
  }

  // ─── Mention Dropdown ───

  Widget _buildMentionDropdown() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 180),
      color: Colors.white,
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: _filteredMembers.length,
        itemBuilder: (_, i) {
          final m = _filteredMembers[i];
          final name = m['fullName']?.toString() ??
              m['userName']?.toString() ??
              '';
          return ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 14,
              backgroundColor: _appBarColor,
              child: Text(
                name.isNotEmpty ? name[0] : '?',
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
            title: Text(name, style: const TextStyle(fontSize: 14)),
            onTap: () => _insertMention(m),
          );
        },
      ),
    );
  }

  // ─── Input Bar ───

  Widget _buildUploadIndicator() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('جاري رفع $_uploadFileName', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                const LinearProgressIndicator(minHeight: 3),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return Container(
      color: _inputBarColor,
      padding: EdgeInsets.only(
        left: isMobile ? 4 : 6,
        right: isMobile ? 4 : 6,
        top: isMobile ? 4 : 6,
        bottom: MediaQuery.of(context).padding.bottom + (isMobile ? 4 : 6),
      ),
      child: Row(
        children: [
          // Attachment button
          IconButton(
            icon: const Icon(Icons.attach_file, color: Colors.grey),
            onPressed: _showAttachmentSheet,
          ),

          // Recording indicator or text field
          Expanded(
            child: _isRecording
                ? Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.mic, color: Colors.red.shade400, size: 20),
                        const SizedBox(width: 8),
                        const Text(
                          'جاري التسجيل...',
                          style: TextStyle(color: Colors.red, fontSize: 14),
                        ),
                        const Spacer(),
                        InkWell(
                          onTap: () {
                            if (mounted) setState(() => _isRecording = false);
                          },
                          child: Icon(Icons.delete,
                              color: Colors.red.shade400, size: 20),
                        ),
                      ],
                    ),
                  )
                : Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: TextField(
                      controller: _textController,
                      focusNode: _textFocusNode,
                      onChanged: _onTextChanged,
                      textDirection: TextDirection.rtl,
                      maxLines: isMobile ? 3 : 5,
                      minLines: 1,
                      decoration: const InputDecoration(
                        hintText: 'اكتب رسالة...',
                        hintTextDirection: TextDirection.rtl,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                      ),
                      onSubmitted: (_) => _sendTextMessage(),
                    ),
                  ),
          ),

          const SizedBox(width: 4),

          // زر إرسال / ميكروفون (يتبدل حسب النص)
          CircleAvatar(
            backgroundColor: _appBarColor,
            radius: isMobile ? 19 : 22,
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: Icon(
                _isRecording ? Icons.stop
                    : _textController.text.trim().isNotEmpty ? Icons.send : Icons.mic,
                color: Colors.white,
                size: isMobile ? 18 : 20,
              ),
              onPressed: _isRecording
                  ? _stopRecordingAndSend
                  : _textController.text.trim().isNotEmpty
                      ? _sendTextMessage
                      : _startRecording,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Sender Color (deterministic by userId) ───

  Color _getSenderColor(String userId) {
    final colors = [
      const Color(0xFF1976D2),
      const Color(0xFF388E3C),
      const Color(0xFFD32F2F),
      const Color(0xFF7B1FA2),
      const Color(0xFFF57C00),
      const Color(0xFF0097A7),
      const Color(0xFF5D4037),
      const Color(0xFFC2185B),
    ];
    final hash = userId.hashCode.abs();
    return colors[hash % colors.length];
  }
}

class _AttachItem {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _AttachItem(this.icon, this.label, this.color, this.onTap);
}
