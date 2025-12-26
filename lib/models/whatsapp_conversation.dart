import 'package:cloud_firestore/cloud_firestore.dart';

/// نموذج بيانات المحادثة
class WhatsAppConversation {
  final String phoneNumber;
  final String? userName; // اسم المستخدم
  final String lastMessage;
  final DateTime lastMessageTime;
  final String lastMessageType;
  final int unreadCount;
  final bool isIncoming;
  final DateTime? updatedAt;

  WhatsAppConversation({
    required this.phoneNumber,
    this.userName,
    required this.lastMessage,
    required this.lastMessageTime,
    this.lastMessageType = 'text',
    this.unreadCount = 0,
    this.isIncoming = false,
    this.updatedAt,
  });

  factory WhatsAppConversation.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    // معالجة lastMessageTime - دعم Timestamp و Unix timestamp (int)
    DateTime lastMessageTime = DateTime.now();
    final lastMessageTimeData = data['lastMessageTime'];
    if (lastMessageTimeData is Timestamp) {
      lastMessageTime = lastMessageTimeData.toDate();
    } else if (lastMessageTimeData is int) {
      lastMessageTime =
          DateTime.fromMillisecondsSinceEpoch(lastMessageTimeData * 1000);
    } else if (lastMessageTimeData is String) {
      lastMessageTime = DateTime.fromMillisecondsSinceEpoch(
          int.parse(lastMessageTimeData) * 1000);
    }

    // معالجة updatedAt
    DateTime? updatedAt;
    final updatedAtData = data['updatedAt'];
    if (updatedAtData is Timestamp) {
      updatedAt = updatedAtData.toDate();
    } else if (updatedAtData is int) {
      updatedAt = DateTime.fromMillisecondsSinceEpoch(updatedAtData);
    } else if (updatedAtData is String) {
      updatedAt = DateTime.fromMillisecondsSinceEpoch(int.parse(updatedAtData));
    }

    return WhatsAppConversation(
      phoneNumber: doc.id,
      userName: data['userName'] ?? data['contactName'],
      lastMessage: data['lastMessage'] ?? '',
      lastMessageTime: lastMessageTime,
      lastMessageType: data['lastMessageType'] ?? 'text',
      unreadCount: data['unreadCount'] ?? 0,
      isIncoming: data['isIncoming'] ?? false,
      updatedAt: updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'phoneNumber': phoneNumber,
      if (userName != null) 'userName': userName,
      'lastMessage': lastMessage,
      'lastMessageTime': Timestamp.fromDate(lastMessageTime),
      'lastMessageType': lastMessageType,
      'unreadCount': unreadCount,
      'isIncoming': isIncoming,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  String get formattedPhone {
    // تنسيق الرقم للعرض
    if (phoneNumber.startsWith('964')) {
      return '+${phoneNumber.substring(0, 3)} ${phoneNumber.substring(3)}';
    }
    return phoneNumber;
  }
}

/// نموذج بيانات الرسالة
class WhatsAppMessage {
  final String messageId;
  final String phoneNumber; // from أو to
  final String text;
  final String type;
  final DateTime timestamp;
  final bool isIncoming;
  final String status; // pending, sent, delivered, read, failed
  final DateTime? statusUpdatedAt;

  WhatsAppMessage({
    required this.messageId,
    required this.phoneNumber,
    required this.text,
    this.type = 'text',
    required this.timestamp,
    required this.isIncoming,
    this.status = 'pending',
    this.statusUpdatedAt,
  });

  factory WhatsAppMessage.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    // معالجة timestamp - دعم Timestamp و Unix timestamp (int)
    DateTime timestamp = DateTime.now();
    final timestampData = data['timestamp'];
    if (timestampData is Timestamp) {
      timestamp = timestampData.toDate();
    } else if (timestampData is int) {
      timestamp = DateTime.fromMillisecondsSinceEpoch(timestampData * 1000);
    } else if (timestampData is String) {
      timestamp =
          DateTime.fromMillisecondsSinceEpoch(int.parse(timestampData) * 1000);
    }

    // معالجة statusUpdatedAt
    DateTime? statusUpdatedAt;
    final statusUpdatedAtData = data['statusUpdatedAt'];
    if (statusUpdatedAtData is Timestamp) {
      statusUpdatedAt = statusUpdatedAtData.toDate();
    } else if (statusUpdatedAtData is int) {
      statusUpdatedAt =
          DateTime.fromMillisecondsSinceEpoch(statusUpdatedAtData);
    } else if (statusUpdatedAtData is String) {
      statusUpdatedAt =
          DateTime.fromMillisecondsSinceEpoch(int.parse(statusUpdatedAtData));
    }

    // معالجة phoneNumber - دعم صيغة n8n (phoneNumber فقط بدون from/to)
    String phoneNumber =
        data['phoneNumber'] ?? data['from'] ?? data['to'] ?? '';

    // معالجة text - قد يكون مباشر أو في direction
    String text = data['text'] ?? '';

    // معالجة type - قد يكون messageType
    String type = data['type'] ?? data['messageType'] ?? 'text';

    // معالجة isIncoming - من direction إذا موجود
    bool isIncoming = data['isIncoming'] ?? (data['direction'] == 'incoming');

    return WhatsAppMessage(
      messageId: data['messageId'] ?? doc.id,
      phoneNumber: phoneNumber,
      text: text,
      type: type,
      timestamp: timestamp,
      isIncoming: isIncoming,
      status: data['status'] ?? 'received',
      statusUpdatedAt: statusUpdatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'messageId': messageId,
      if (isIncoming) 'from': phoneNumber else 'to': phoneNumber,
      'text': text,
      'type': type,
      'timestamp': Timestamp.fromDate(timestamp),
      'isIncoming': isIncoming,
      'status': status,
      if (statusUpdatedAt != null)
        'statusUpdatedAt': Timestamp.fromDate(statusUpdatedAt!),
    };
  }

  String get statusIcon {
    switch (status) {
      case 'sent':
        return '✓';
      case 'delivered':
        return '✓✓';
      case 'read':
        return '✓✓';
      case 'failed':
        return '✗';
      default:
        return '○';
    }
  }

  String get typeIcon {
    switch (type) {
      case 'image':
        return '📷';
      case 'video':
        return '🎥';
      case 'audio':
        return '🎤';
      case 'document':
        return '📄';
      case 'location':
        return '📍';
      case 'contacts':
        return '👤';
      default:
        return '💬';
    }
  }
}
