import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/whatsapp_conversation.dart';
import '../services/whatsapp_conversation_service.dart';
import 'whatsapp_chat_page.dart';

/// صفحة عرض جميع محادثات WhatsApp
class WhatsAppConversationsPage extends StatefulWidget {
  final bool isAdmin;

  const WhatsAppConversationsPage({super.key, this.isAdmin = false});

  @override
  State<WhatsAppConversationsPage> createState() =>
      _WhatsAppConversationsPageState();
}

class _WhatsAppConversationsPageState extends State<WhatsAppConversationsPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    // استخدام الصلاحية الممررة من الـ widget
    _isAdmin = widget.isAdmin;
    debugPrint('👤 صلاحيات المدير في صفحة المحادثات: $_isAdmin');
    // بدء مراقبة الرسائل الواردة الجديدة
    WhatsAppConversationService.startIncomingMessagesListener();
    // مزامنة المحادثات من الرسائل الموجودة
    WhatsAppConversationService.syncConversationsFromMessages();
    // مزامنة الأسماء من الرسائل عند فتح الصفحة
    WhatsAppConversationService.syncNamesFromMessages();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.chat_bubble, size: 20),
            ),
            const SizedBox(width: 12),
            const Text(
              'محادثات WhatsApp',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ],
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF25D366), Color(0xFF128C7E)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: [
          // عدد الرسائل غير المقروءة
          StreamBuilder<int>(
            stream: WhatsAppConversationService.getUnreadCount(),
            builder: (context, snapshot) {
              final unreadCount = snapshot.data ?? 0;
              if (unreadCount == 0) return const SizedBox.shrink();

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withValues(alpha: 0.4),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.notifications_active,
                          size: 14, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(
                        '$unreadCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() {}),
            tooltip: 'تحديث',
          ),
        ],
      ),
      body: Column(
        children: [
          // شريط البحث
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.grey[50]!, Colors.white],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: const Color(0xFF25D366).withValues(alpha: 0.3),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF25D366).withValues(alpha: 0.15),
                    blurRadius: 15,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'البحث في المحادثات والأسماء...',
                  hintStyle: TextStyle(color: Colors.grey[400]),
                  prefixIcon: Container(
                    padding: const EdgeInsets.all(10),
                    child: const Icon(Icons.search_rounded,
                        color: Color(0xFF25D366), size: 26),
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? Container(
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            shape: BoxShape.circle,
                          ),
                          margin: const EdgeInsets.all(8),
                          child: IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            color: Colors.grey[700],
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          ),
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                ),
                onChanged: (value) => setState(() => _searchQuery = value),
              ),
            ),
          ),

          // قائمة المحادثات
          Expanded(
            child: StreamBuilder<List<WhatsAppConversation>>(
              stream: WhatsAppConversationService.getConversations(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 64, color: Colors.red),
                        const SizedBox(height: 16),
                        Text('حدث خطأ: ${snapshot.error}'),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () => setState(() {}),
                          icon: const Icon(Icons.refresh),
                          label: const Text('إعادة المحاولة'),
                        ),
                      ],
                    ),
                  );
                }

                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                var conversations = snapshot.data!;

                // تطبيق البحث
                if (_searchQuery.isNotEmpty) {
                  conversations = conversations
                      .where((conv) =>
                          conv.phoneNumber.contains(_searchQuery) ||
                          (conv.userName != null &&
                              conv.userName!
                                  .toLowerCase()
                                  .contains(_searchQuery.toLowerCase())) ||
                          conv.lastMessage
                              .toLowerCase()
                              .contains(_searchQuery.toLowerCase()))
                      .toList();
                }

                if (conversations.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _searchQuery.isEmpty
                              ? Icons.chat_bubble_outline
                              : Icons.search_off,
                          size: 80,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _searchQuery.isEmpty
                              ? 'لا توجد محادثات بعد'
                              : 'لم يتم العثور على نتائج',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                          ),
                        ),
                        if (_searchQuery.isEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            'عندما يرد العملاء على رسائلك،\nستظهر محادثاتهم هنا',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey[500]),
                          ),
                        ],
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  itemCount: conversations.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final conversation = conversations[index];
                    return _buildConversationTile(conversation);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConversationTile(WhatsAppConversation conversation) {
    final timeFormat = DateFormat('HH:mm');
    final dateFormat = DateFormat('dd/MM/yyyy');
    final now = DateTime.now();
    final isToday = conversation.lastMessageTime.year == now.year &&
        conversation.lastMessageTime.month == now.month &&
        conversation.lastMessageTime.day == now.day;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white,
        border: Border.all(
          color: Colors.black,
          width: conversation.unreadCount > 0 ? 2.5 : 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: conversation.unreadCount > 0
                ? const Color(0xFF25D366).withValues(alpha: 0.2)
                : Colors.black.withValues(alpha: 0.08),
            blurRadius: conversation.unreadCount > 0 ? 12 : 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Color(0xFF25D366), Color(0xFF128C7E)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF25D366).withValues(alpha: 0.4),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: CircleAvatar(
            backgroundColor: Colors.transparent,
            radius: 28,
            child: Text(
              conversation.phoneNumber
                  .substring(conversation.phoneNumber.length - 2),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (conversation.userName != null &&
                      conversation.userName!.isNotEmpty)
                    Text(
                      conversation.userName!,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  Text(
                    conversation.formattedPhone,
                    style: TextStyle(
                      fontWeight: conversation.userName != null &&
                              conversation.userName!.isNotEmpty
                          ? FontWeight.normal
                          : FontWeight.bold,
                      fontSize: conversation.userName != null &&
                              conversation.userName!.isNotEmpty
                          ? 13
                          : 16,
                      color: conversation.userName != null &&
                              conversation.userName!.isNotEmpty
                          ? Colors.grey[600]
                          : null,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              isToday
                  ? timeFormat.format(conversation.lastMessageTime)
                  : dateFormat.format(conversation.lastMessageTime),
              style: TextStyle(
                fontSize: 12,
                color: conversation.unreadCount > 0
                    ? const Color(0xFF25D366)
                    : Colors.grey[600],
              ),
            ),
          ],
        ),
        subtitle: Row(
          children: [
            if (!conversation.isIncoming)
              Icon(
                Icons.done_all,
                size: 16,
                color: Colors.grey[600],
              ),
            if (!conversation.isIncoming) const SizedBox(width: 4),
            Expanded(
              child: Text(
                conversation.lastMessage,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: conversation.unreadCount > 0
                      ? Colors.black87
                      : Colors.grey[600],
                  fontWeight: conversation.unreadCount > 0
                      ? FontWeight.w600
                      : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (conversation.unreadCount > 0)
              Container(
                padding: const EdgeInsets.all(8),
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
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Text(
                  '${conversation.unreadCount}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            if (conversation.unreadCount > 0) const SizedBox(width: 8),
            // زر الحذف للمدراء فقط
            Builder(
              builder: (builderContext) {
                debugPrint('🔍 عرض زر الحذف: _isAdmin = $_isAdmin');
                if (!_isAdmin) return const SizedBox.shrink();
                return IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  tooltip: 'حذف المحادثة',
                  onPressed: () async {
                    // حفظ مرجع ScaffoldMessenger قبل العمليات غير المتزامنة
                    final scaffoldMessenger =
                        ScaffoldMessenger.of(builderContext);

                    final confirm = await showDialog<bool>(
                      context: builderContext,
                      builder: (dialogContext) => AlertDialog(
                        title: const Text('تأكيد الحذف'),
                        content:
                            const Text('هل أنت متأكد من حذف هذه المحادثة؟'),
                        actions: [
                          TextButton(
                            onPressed: () =>
                                Navigator.pop(dialogContext, false),
                            child: const Text('إلغاء'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext, true),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.red,
                            ),
                            child: const Text('حذف'),
                          ),
                        ],
                      ),
                    );

                    if (confirm == true && mounted) {
                      try {
                        debugPrint(
                            '🗑️ محاولة حذف المحادثة: ${conversation.phoneNumber}');
                        await WhatsAppConversationService.deleteConversation(
                            conversation.phoneNumber);
                        debugPrint('✅ تم حذف المحادثة بنجاح');
                        if (mounted) {
                          scaffoldMessenger.showSnackBar(
                            const SnackBar(
                              content: Text('تم حذف المحادثة بنجاح'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        debugPrint('❌ خطأ في حذف المحادثة');
                        if (mounted) {
                          scaffoldMessenger.showSnackBar(
                            SnackBar(
                              content: Text('حدث خطأ أثناء حذف المحادثة'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    }
                  },
                );
              },
            ),
          ],
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => WhatsAppChatPage(
                phoneNumber: conversation.phoneNumber,
              ),
            ),
          );
        },
        onLongPress: () => _showConversationOptions(conversation),
      ),
    );
  }

  void _showConversationOptions(WhatsAppConversation conversation) {
    // حفظ مرجع ScaffoldMessenger قبل فتح القائمة
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    showModalBottomSheet(
      context: context,
      builder: (bottomSheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.done_all, color: Color(0xFF25D366)),
              title: const Text('تعليم كمقروء'),
              onTap: () async {
                Navigator.pop(bottomSheetContext);
                await WhatsAppConversationService.markAsRead(
                    conversation.phoneNumber);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('حذف المحادثة'),
              onTap: () async {
                Navigator.pop(bottomSheetContext);

                if (!mounted) return;

                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('تأكيد الحذف'),
                    content: const Text(
                        'هل أنت متأكد من حذف هذه المحادثة؟\nسيتم حذف جميع الرسائل.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('إلغاء'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                        child: const Text('حذف'),
                      ),
                    ],
                  ),
                );

                if (confirm == true && mounted) {
                  try {
                    debugPrint(
                        '🗑️ محاولة حذف المحادثة (long press): ${conversation.phoneNumber}');
                    await WhatsAppConversationService.deleteConversation(
                        conversation.phoneNumber);
                    debugPrint('✅ تم حذف المحادثة بنجاح');
                    if (mounted) {
                      scaffoldMessenger.showSnackBar(
                        const SnackBar(
                          content: Text('تم حذف المحادثة بنجاح'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    debugPrint('❌ خطأ في حذف المحادثة');
                    if (mounted) {
                      scaffoldMessenger.showSnackBar(
                        SnackBar(
                          content: Text('حدث خطأ أثناء حذف المحادثة'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
