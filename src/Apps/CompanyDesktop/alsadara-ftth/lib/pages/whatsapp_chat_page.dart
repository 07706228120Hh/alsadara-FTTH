import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import '../models/whatsapp_conversation.dart';
import '../services/whatsapp_conversation_service.dart';
import '../services/whatsapp_business_service.dart';

/// صفحة المحادثة الفردية
class WhatsAppChatPage extends StatefulWidget {
  final String phoneNumber;

  const WhatsAppChatPage({
    super.key,
    required this.phoneNumber,
  });

  @override
  State<WhatsAppChatPage> createState() => _WhatsAppChatPageState();
}

class _WhatsAppChatPageState extends State<WhatsAppChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isSending = false;

  /// كاش الوسائط المحملة (mediaId -> bytes)
  final Map<String, Uint8List> _mediaCache = {};

  /// قائمة الوسائط قيد التحميل
  final Set<String> _loadingMedia = {};

  /// مجلد التخزين الدائم للوسائط
  Directory? _mediaCacheDir;

  @override
  void initState() {
    super.initState();
    WhatsAppConversationService.markAsRead(widget.phoneNumber);
    _initMediaCacheDir();
  }

  /// تهيئة مجلد الكاش الدائم
  Future<void> _initMediaCacheDir() async {
    final appDir = await getApplicationSupportDirectory();
    _mediaCacheDir = Directory('${appDir.path}/whatsapp_media');
    if (!await _mediaCacheDir!.exists()) {
      await _mediaCacheDir!.create(recursive: true);
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty || _isSending) return;

    setState(() => _isSending = true);

    try {
      // إرسال عبر WhatsApp Business API
      final result = await WhatsAppBusinessService.sendTextMessage(
        to: widget.phoneNumber,
        message: message,
      );

      if (result != null) {
        // حفظ في Firestore
        await WhatsAppConversationService.sendMessage(
          phoneNumber: widget.phoneNumber,
          message: message,
        );

        _messageController.clear();
        _scrollToBottom();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('فشل في إرسال الرسالة'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF25D366), Color(0xFF128C7E)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Row(
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: CircleAvatar(
                backgroundColor: Colors.white,
                radius: 20,
                child: Text(
                  widget.phoneNumber.substring(widget.phoneNumber.length - 2),
                  style: const TextStyle(
                    color: Color(0xFF25D366),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatPhoneNumber(widget.phoneNumber),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Text(
                  'WhatsApp',
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.phone),
            onPressed: () {
              // يمكن إضافة وظيفة للاتصال
            },
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () => _showChatOptions(),
          ),
        ],
      ),
      body: Column(
        children: [
          // قائمة الرسائل
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFFECE5DD).withValues(alpha: 0.3),
                    const Color(0xFFD1D7DB).withValues(alpha: 0.2),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: StreamBuilder<List<WhatsAppMessage>>(
                stream:
                    WhatsAppConversationService.getMessages(widget.phoneNumber),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Text('حدث خطأ: ${snapshot.error}'),
                    );
                  }

                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final messages = snapshot.data!;

                  if (messages.isEmpty) {
                    return const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.chat_bubble_outline,
                              size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text(
                            'لا توجد رسائل بعد',
                            style: TextStyle(fontSize: 18, color: Colors.grey),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'ابدأ بإرسال رسالة',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    );
                  }

                  // التمرير للأسفل عند تحميل رسائل جديدة
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _scrollToBottom();
                  });

                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      return _buildMessageBubble(message);
                    },
                  );
                },
              ),
            ),
          ),

          // حقل إدخال الرسالة
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.grey[50]!, Colors.white],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, -3),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF25D366).withValues(alpha: 0.1),
                          blurRadius: 10,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _messageController,
                      decoration: InputDecoration(
                        hintText: 'اكتب رسالة...',
                        hintStyle: TextStyle(color: Colors.grey[400]),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        prefixIcon: Icon(Icons.emoji_emotions_outlined,
                            color: Colors.grey[400]),
                      ),
                      maxLines: null,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF25D366), Color(0xFF128C7E)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF25D366).withValues(alpha: 0.5),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: CircleAvatar(
                    backgroundColor: Colors.transparent,
                    radius: 26,
                    child: _isSending
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : IconButton(
                            icon: const Icon(Icons.send, color: Colors.white),
                            onPressed: _sendMessage,
                            iconSize: 22,
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(WhatsAppMessage message) {
    final timeFormat = DateFormat('HH:mm');
    final isMe = !message.isIncoming;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isMe) const SizedBox(width: 12),
          // أيقونة النسخ للرسائل الواردة (على اليسار)
          if (!isMe) _buildCopyButton(message.text),
          Flexible(
            child: GestureDetector(
              onLongPress: () => _showMessageOptions(message),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  gradient: isMe
                      ? const LinearGradient(
                          colors: [Color(0xFFDCF8C6), Color(0xFFCFF5BC)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : LinearGradient(
                          colors: [Colors.white, Colors.grey[50]!],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(20),
                    topRight: const Radius.circular(20),
                    bottomLeft: Radius.circular(isMe ? 20 : 4),
                    bottomRight: Radius.circular(isMe ? 4 : 20),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isMe
                          ? const Color(0xFF25D366).withValues(alpha: 0.15)
                          : Colors.black.withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // عرض الوسائط إن وُجدت
                    if (message.hasMedia) ...[
                      _buildMediaContent(message),
                      if (message.text.isNotEmpty &&
                          !message.text.startsWith('['))
                        const SizedBox(height: 6),
                    ],
                    // نص الرسالة - قابل للتحديد والنسخ
                    if (!message.hasMedia ||
                        (message.text.isNotEmpty &&
                            !message.text.startsWith('[')))
                      SelectableText(
                        message.text,
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.grey[900],
                          height: 1.4,
                        ),
                      ),
                    const SizedBox(height: 6),
                    // الوقت والحالة
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 12,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          timeFormat.format(message.timestamp),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (isMe) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: message.status == 'read'
                                  ? const Color(0xFF25D366)
                                  : Colors.grey[400],
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              message.status == 'read'
                                  ? Icons.done_all
                                  : Icons.done,
                              size: 12,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          // أيقونة النسخ للرسائل الصادرة (على اليمين)
          if (isMe) _buildCopyButton(message.text),
          if (isMe) const SizedBox(width: 12),
        ],
      ),
    );
  }

  /// عرض محتوى الوسائط حسب النوع
  Widget _buildMediaContent(WhatsAppMessage message) {
    if (message.isImage) {
      return _buildImageMedia(message);
    } else if (message.isAudio) {
      return _buildAudioMedia(message);
    } else if (message.isVideo) {
      return _buildVideoMedia(message);
    } else if (message.isDocument) {
      return _buildDocumentMedia(message);
    }
    // نوع غير معروف — أيقونة عامة
    return _buildGenericMedia(message);
  }

  /// عرض صورة
  Widget _buildImageMedia(WhatsAppMessage message) {
    final mediaId = message.mediaId!;
    final mime = message.mimeType ?? 'image/jpeg';

    // إذا الصورة محملة في الكاش
    if (_mediaCache.containsKey(mediaId)) {
      return GestureDetector(
        onTap: () => _showFullImage(_mediaCache[mediaId]!),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280, maxHeight: 300),
            child: Image.memory(
              _mediaCache[mediaId]!,
              fit: BoxFit.cover,
            ),
          ),
        ),
      );
    }

    // محاولة تحميل من القرص تلقائياً
    if (!_loadingMedia.contains(mediaId)) {
      _downloadAndCacheMedia(mediaId, mime);
    }

    // عرض مؤشر تحميل
    return Container(
      width: 200,
      height: 150,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(height: 8),
            Text('جاري تحميل الصورة...', style: TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }

  /// عرض رسالة صوتية
  Widget _buildAudioMedia(WhatsAppMessage message) {
    final mediaId = message.mediaId!;
    final mime = message.mimeType ?? 'audio/ogg';
    final isLoaded = _mediaCache.containsKey(mediaId);
    final isLoading = _loadingMedia.contains(mediaId);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: isLoading
                ? null
                : isLoaded
                    ? () => _openMediaFile(mediaId, mime)
                    : () async {
                        await _downloadAndCacheMedia(mediaId, mime);
                        if (_mediaCache.containsKey(mediaId)) {
                          _openMediaFile(mediaId, mime);
                        }
                      },
            child: Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: Color(0xFF25D366),
                shape: BoxShape.circle,
              ),
              child: isLoading
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      isLoaded ? Icons.play_arrow : Icons.download,
                      color: Colors.white,
                      size: 24,
                    ),
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'رسالة صوتية',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[800],
                ),
              ),
              Text(
                isLoaded
                    ? 'اضغط للتشغيل'
                    : isLoading
                        ? 'جاري التحميل...'
                        : 'اضغط للتحميل',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// عرض فيديو
  Widget _buildVideoMedia(WhatsAppMessage message) {
    final mediaId = message.mediaId!;
    final mime = message.mimeType ?? 'video/mp4';
    final isLoaded = _mediaCache.containsKey(mediaId);
    final isLoading = _loadingMedia.contains(mediaId);

    return GestureDetector(
      onTap: isLoading
          ? null
          : isLoaded
              ? () => _openMediaFile(mediaId, mime)
              : () async {
                  await _downloadAndCacheMedia(mediaId, mime);
                  if (_mediaCache.containsKey(mediaId)) {
                    _openMediaFile(mediaId, mime);
                  }
                },
      child: Container(
        width: 220,
        height: 160,
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isLoading)
                const SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              else
                Icon(
                  isLoaded ? Icons.play_circle_filled : Icons.download,
                  size: 52,
                  color: Colors.white,
                ),
              const SizedBox(height: 8),
              Text(
                isLoaded
                    ? 'فيديو (تم التحميل)'
                    : isLoading
                        ? 'جاري تحميل الفيديو...'
                        : 'اضغط لتحميل الفيديو',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// عرض مستند
  Widget _buildDocumentMedia(WhatsAppMessage message) {
    final mediaId = message.mediaId!;
    final mime = message.mimeType ?? 'application/octet-stream';
    final isLoaded = _mediaCache.containsKey(mediaId);
    final isLoading = _loadingMedia.contains(mediaId);
    final fileName = message.mediaFileName ?? message.text;

    return GestureDetector(
      onTap: isLoading
          ? null
          : isLoaded
              ? () => _openMediaFile(mediaId, mime)
              : () async {
                  await _downloadAndCacheMedia(mediaId, mime);
                  if (_mediaCache.containsKey(mediaId)) {
                    _openMediaFile(mediaId, mime);
                  }
                },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insert_drive_file, size: 36, color: Colors.blue[700]),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fileName,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[800],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isLoading ? 'جاري التحميل...' : 'اضغط للتحميل',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
            if (isLoading)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(Icons.download, color: Colors.grey[500]),
          ],
        ),
      ),
    );
  }

  /// عرض وسائط غير معروفة
  Widget _buildGenericMedia(WhatsAppMessage message) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.attachment, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Text(
            message.type,
            style: TextStyle(fontSize: 13, color: Colors.grey[700]),
          ),
        ],
      ),
    );
  }

  /// الحصول على مسار ملف الكاش لوسائط معينة
  String? _getCacheFilePath(String mediaId, [String? mimeType]) {
    if (_mediaCacheDir == null) return null;
    final ext = _getExtFromMime(mimeType ?? '');
    return '${_mediaCacheDir!.path}/$mediaId.$ext';
  }

  /// تحميل وسائط من القرص إذا موجودة
  Future<bool> _loadFromDiskCache(String mediaId, [String? mimeType]) async {
    if (_mediaCache.containsKey(mediaId)) return true;
    final path = _getCacheFilePath(mediaId, mimeType);
    if (path == null) return false;
    final file = File(path);
    if (await file.exists()) {
      final bytes = await file.readAsBytes();
      if (mounted) {
        setState(() => _mediaCache[mediaId] = bytes);
      }
      return true;
    }
    return false;
  }

  /// تحميل الوسائط من الإنترنت وتخزينها في الكاش والقرص
  Future<void> _downloadAndCacheMedia(String mediaId, [String? mimeType]) async {
    if (_loadingMedia.contains(mediaId) || _mediaCache.containsKey(mediaId)) {
      return;
    }

    // محاولة التحميل من القرص أولاً
    if (await _loadFromDiskCache(mediaId, mimeType)) return;

    setState(() => _loadingMedia.add(mediaId));

    try {
      final bytes = await WhatsAppBusinessService.downloadMedia(mediaId);
      if (bytes != null && mounted) {
        // حفظ على القرص
        final path = _getCacheFilePath(mediaId, mimeType);
        if (path != null) {
          try {
            await File(path).writeAsBytes(bytes);
          } catch (_) {}
        }
        setState(() {
          _mediaCache[mediaId] = bytes;
          _loadingMedia.remove(mediaId);
        });
      } else if (mounted) {
        setState(() => _loadingMedia.remove(mediaId));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('فشل في تحميل الوسائط'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingMedia.remove(mediaId));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('خطأ في تحميل الوسائط'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// استخراج امتداد الملف من نوع MIME
  static String _getExtFromMime(String mimeType) {
    if (mimeType.contains('ogg')) return 'ogg';
    if (mimeType.contains('mp4')) return 'mp4';
    if (mimeType.contains('mpeg') || mimeType.contains('mp3')) return 'mp3';
    if (mimeType.contains('wav')) return 'wav';
    if (mimeType.contains('webp')) return 'webp';
    if (mimeType.contains('jpeg') || mimeType.contains('jpg')) return 'jpg';
    if (mimeType.contains('png')) return 'png';
    if (mimeType.contains('pdf')) return 'pdf';
    if (mimeType.contains('webm')) return 'webm';
    return 'bin';
  }

  /// فتح ملف الوسائط المحفوظ بمشغل النظام
  Future<void> _openMediaFile(String mediaId, String mimeType) async {
    try {
      final path = _getCacheFilePath(mediaId, mimeType);
      if (path == null) return;
      final file = File(path);
      if (!await file.exists()) {
        // لو الملف غير موجود على القرص، احفظه من الكاش
        final bytes = _mediaCache[mediaId];
        if (bytes == null) return;
        await file.writeAsBytes(bytes);
      }
      await OpenFile.open(path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('فشل في فتح الملف'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// عرض الصورة بحجم كامل
  void _showFullImage(Uint8List imageBytes) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: Image.memory(imageBytes),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon:
                    const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// زر نسخ النص
  Widget _buildCopyButton(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        onTap: () => _copyText(text),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.grey[200]?.withValues(alpha: 0.7),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.copy,
            size: 16,
            color: Colors.grey[600],
          ),
        ),
      ),
    );
  }

  /// نسخ النص إلى الحافظة
  void _copyText(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text('تم نسخ النص'),
          ],
        ),
        backgroundColor: const Color(0xFF25D366),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// عرض خيارات الرسالة عند الضغط المطول
  void _showMessageOptions(WhatsAppMessage message) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF25D366).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.copy, color: Color(0xFF25D366)),
                ),
                title: const Text('نسخ النص'),
                subtitle: Text(
                  message.text.length > 50
                      ? '${message.text.substring(0, 50)}...'
                      : message.text,
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _copyText(message.text);
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.select_all, color: Colors.blue),
                ),
                title: const Text('تحديد الكل'),
                onTap: () {
                  Navigator.pop(context);
                  // سيتم التحديد تلقائياً مع SelectableText
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('اضغط مطولاً على النص لتحديده'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatPhoneNumber(String phone) {
    if (phone.startsWith('964')) {
      return '+${phone.substring(0, 3)} ${phone.substring(3)}';
    }
    return phone;
  }

  void _showChatOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('نسخ رقم الهاتف'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: widget.phoneNumber));
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم نسخ الرقم')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
