import 'package:flutter/material.dart';
import 'dart:async';
import '../models/task.dart';

class RealTimeMessagingService {
  static final RealTimeMessagingService _instance =
      RealTimeMessagingService._internal();
  factory RealTimeMessagingService() => _instance;
  RealTimeMessagingService._internal();

  final StreamController<TaskMessage> _messageController =
      StreamController.broadcast();
  Stream<TaskMessage> get messageStream => _messageController.stream;

  // إرسال رسالة فورية
  void sendTaskMessage({
    required String taskId,
    required String message,
    required String senderName,
    required String senderRole,
    MessageType type = MessageType.info,
  }) {
    final taskMessage = TaskMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      taskId: taskId,
      message: message,
      senderName: senderName,
      senderRole: senderRole,
      timestamp: DateTime.now(),
      type: type,
    );

    _messageController.add(taskMessage);
  }

  // إشعارات تلقائية للأحداث المهمة
  void notifyTaskEvent(Task task, TaskEvent event, String userName) {
    String message;
    MessageType type;

    switch (event) {
      case TaskEvent.created:
        message = 'تم إنشاء مهمة جديدة: ${task.title}';
        type = MessageType.success;
        break;
      case TaskEvent.statusChanged:
        message = 'تم تغيير حالة المهمة "${task.title}" إلى ${task.status}';
        type = MessageType.info;
        break;
      case TaskEvent.assigned:
        message = 'تم تعيين المهمة "${task.title}" للفني ${task.technician}';
        type = MessageType.info;
        break;
      case TaskEvent.completed:
        message = 'تم إكمال المهمة "${task.title}" بنجاح!';
        type = MessageType.success;
        break;
      case TaskEvent.overdue:
        message = 'تحذير: المهمة "${task.title}" متأخرة عن الموعد المحدد';
        type = MessageType.warning;
        break;
      case TaskEvent.cancelled:
        message = 'تم إلغاء المهمة "${task.title}"';
        type = MessageType.error;
        break;
    }

    sendTaskMessage(
      taskId: task.id,
      message: message,
      senderName: 'النظام',
      senderRole: 'system',
      type: type,
    );
  }

  void dispose() {
    _messageController.close();
  }
}

enum TaskEvent {
  created,
  statusChanged,
  assigned,
  completed,
  overdue,
  cancelled
}

enum MessageType { info, success, warning, error }

class TaskMessage {
  final String id;
  final String taskId;
  final String message;
  final String senderName;
  final String senderRole;
  final DateTime timestamp;
  final MessageType type;

  TaskMessage({
    required this.id,
    required this.taskId,
    required this.message,
    required this.senderName,
    required this.senderRole,
    required this.timestamp,
    required this.type,
  });
}

// ويدجت عرض الرسائل الفورية
class LiveMessagesWidget extends StatefulWidget {
  final String? currentTaskId;
  final String userName;
  final String userRole;

  const LiveMessagesWidget({
    super.key,
    this.currentTaskId,
    required this.userName,
    required this.userRole,
  });

  @override
  _LiveMessagesWidgetState createState() => _LiveMessagesWidgetState();
}

class _LiveMessagesWidgetState extends State<LiveMessagesWidget>
    with TickerProviderStateMixin {
  final List<TaskMessage> _messages = [];
  late StreamSubscription<TaskMessage> _messageSubscription;
  late AnimationController _fadeController;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: Duration(milliseconds: 300),
      vsync: this,
    );

    _messageSubscription =
        RealTimeMessagingService().messageStream.listen((message) {
      // فلترة الرسائل حسب المهمة الحالية أو عرض جميع الرسائل
      if (widget.currentTaskId == null ||
          message.taskId == widget.currentTaskId) {
        setState(() {
          _messages.insert(0, message);
          // الاحتفاظ بآخر 50 رسالة فقط
          if (_messages.length > 50) {
            _messages.removeLast();
          }
        });
        _fadeController.forward();
        _scrollToTop();
      }
    });
  }

  @override
  void dispose() {
    _messageSubscription.cancel();
    _fadeController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 300,
      margin: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          // عنوان الرسائل
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue.shade600, Colors.blue.shade400],
              ),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.message, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text(
                  'الرسائل الفورية',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Spacer(),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_messages.length}',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // قائمة الرسائل
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.message_outlined,
                            size: 48, color: Colors.grey.shade400),
                        SizedBox(height: 8),
                        Text(
                          'لا توجد رسائل حالياً',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: EdgeInsets.all(8),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      return FadeTransition(
                        opacity: index == 0
                            ? _fadeController
                            : AlwaysStoppedAnimation(1.0),
                        child: _buildMessageCard(message),
                      );
                    },
                  ),
          ),

          // شريط إرسال الرسائل (إذا كان هناك مهمة محددة)
          if (widget.currentTaskId != null) _buildMessageInputBar(),
        ],
      ),
    );
  }

  Widget _buildMessageCard(TaskMessage message) {
    Color typeColor;
    IconData typeIcon;

    switch (message.type) {
      case MessageType.success:
        typeColor = Colors.green;
        typeIcon = Icons.check_circle;
        break;
      case MessageType.warning:
        typeColor = Colors.orange;
        typeIcon = Icons.warning;
        break;
      case MessageType.error:
        typeColor = Colors.red;
        typeIcon = Icons.error;
        break;
      default:
        typeColor = Colors.blue;
        typeIcon = Icons.info;
    }

    return Container(
      margin: EdgeInsets.symmetric(vertical: 4),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: typeColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: typeColor.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(typeIcon, color: typeColor, size: 16),
              SizedBox(width: 6),
              Text(
                message.senderName,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: typeColor,
                  fontSize: 12,
                ),
              ),
              SizedBox(width: 4),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: typeColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  message.senderRole,
                  style: TextStyle(
                    fontSize: 10,
                    color: typeColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Spacer(),
              Text(
                _formatTime(message.timestamp),
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
          SizedBox(height: 6),
          Text(
            message.message,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageInputBar() {
    final TextEditingController textController = TextEditingController();

    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: textController,
              decoration: InputDecoration(
                hintText: 'اكتب رسالة...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              maxLines: null,
              textInputAction: TextInputAction.send,
              onSubmitted: (text) {
                _sendMessage(text);
                textController.clear();
              },
            ),
          ),
          SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue.shade600, Colors.blue.shade400],
              ),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: Icon(Icons.send, color: Colors.white),
              onPressed: () {
                _sendMessage(textController.text);
                textController.clear();
              },
            ),
          ),
        ],
      ),
    );
  }

  void _sendMessage(String text) {
    if (text.trim().isEmpty) return;

    RealTimeMessagingService().sendTaskMessage(
      taskId: widget.currentTaskId!,
      message: text.trim(),
      senderName: widget.userName,
      senderRole: widget.userRole,
      type: MessageType.info,
    );
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'الآن';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}د';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}س';
    } else {
      return '${dateTime.day}/${dateTime.month}';
    }
  }
}
